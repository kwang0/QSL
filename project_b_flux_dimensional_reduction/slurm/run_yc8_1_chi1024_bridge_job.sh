#!/usr/bin/env bash

# Batch worker for the YC8-1 chi=1024 bridge. Slurm may execute this file from
# a spool directory, so every repository path is supplied explicitly.

set -u

readonly REQUIRED_ALLOCATION_CPUS=18
readonly SOLVER_STEP_CPUS=8
readonly JULIA_THREADS=4

[[ $# -ge 5 && $# -le 6 ]] || {
  printf 'ERROR: worker usage: PROJECT_ROOT CONFIG SHA256 RUN_DIR JULIA [--preflight]\n' >&2
  exit 2
}

project_root="$1"
config_path="$2"
expected_config_sha256="$3"
run_dir="$4"
julia_bin="$5"
preflight=false
if [[ "${6:-}" == --preflight ]]; then
  preflight=true
elif [[ -n "${6:-}" ]]; then
  printf 'ERROR: unknown worker option: %s\n' "$6" >&2
  exit 2
fi

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "sha256sum or shasum is required"
  fi
}

validator="$project_root/scripts/validate_yc8_1_chi1024_bridge_config.jl"
[[ -f "$project_root/Project.toml" ]] || die "missing Project.toml under $project_root"
[[ -f "$project_root/scripts/run_scan.jl" ]] || die "missing scan driver"
[[ -f "$validator" ]] || die "missing YC8-1 bridge validator"
[[ -f "$config_path" ]] || die "missing bridge configuration: $config_path"
[[ "$(sha256_file "$config_path")" == "$expected_config_sha256" ]] ||
  die "configuration SHA-256 changed after submission"
command -v "$julia_bin" >/dev/null 2>&1 || die "Julia is unavailable: $julia_bin"

mkdir -p "$run_dir"
"$julia_bin" --startup-file=no --project="$project_root" "$validator" "$config_path" \
  >"$run_dir/worker-preflight.tsv"

if [[ "$preflight" == true ]]; then
  printf 'YC8-1 chi=1024 bridge worker preflight passed.\n'
  exit 0
fi

command -v srun >/dev/null 2>&1 || die "srun is unavailable"
[[ -x /usr/bin/time ]] || die "/usr/bin/time is unavailable"
allocation_cpus="${SLURM_CPUS_PER_TASK:-0}"
[[ "$allocation_cpus" =~ ^[1-9][0-9]*$ ]] ||
  die "invalid SLURM_CPUS_PER_TASK=$allocation_cpus"
(( allocation_cpus == REQUIRED_ALLOCATION_CPUS )) ||
  die "the bridge allocation needs $REQUIRED_ALLOCATION_CPUS logical CPUs"

job_id="${SLURM_JOB_ID:-}"
[[ "$job_id" =~ ^[1-9][0-9]*$ ]] || die "invalid or missing SLURM_JOB_ID=$job_id"
scratch_root="${PSCRATCH:-${SCRATCH:-}}"
[[ -n "$scratch_root" ]] || die 'neither PSCRATCH nor SCRATCH is defined'
scratch_root="${scratch_root%/}"
[[ "$scratch_root" == /pscratch/* ]] || die "unexpected scratch root: $scratch_root"
[[ -d "$scratch_root" ]] || die "scratch root is unavailable: $scratch_root"
scratch_package="$scratch_root/QSL/project_b_flux_dimensional_reduction/phase1_vumps/yc8_1/job_${job_id}_${expected_config_sha256:0:12}"
checkpoint_directory="$scratch_package/optimizer_checkpoints"
state_directory="$scratch_package/science_states"
[[ ! -e "$scratch_package" ]] || die "scratch package already exists: $scratch_package"
mkdir -p "$checkpoint_directory" "$state_directory"

mkdir -p "$run_dir/metrics"
pretimeout_request="$run_dir/pretimeout.request"
[[ ! -e "$pretimeout_request" ]] || die "stale pre-timeout request exists"

handle_pretimeout() {
  [[ ! -e "$pretimeout_request" ]] || return 0
  local temporary_request="$pretimeout_request.tmp.$$"
  {
    printf 'requested_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'job_id=%s\n' "${SLURM_JOB_ID:-unknown}"
    printf 'signal=USR1\n'
  } >"$temporary_request"
  mv "$temporary_request" "$pretimeout_request"
  printf 'Pre-timeout signal recorded; Julia will checkpoint after the current outer iteration.\n'
}

trap handle_pretimeout USR1
{
  printf 'PROJECT_ROOT=%s\n' "$project_root"
  printf 'CONFIG_PATH=%s\n' "$config_path"
  printf 'CONFIG_SHA256=%s\n' "$expected_config_sha256"
  printf 'SLURM_JOB_ID=%s\n' "$job_id"
  printf 'SLURM_CPUS_PER_TASK=%s\n' "$allocation_cpus"
  printf 'SOLVER_STEP_CPUS=%s\n' "$SOLVER_STEP_CPUS"
  printf 'JULIA_THREADS=%s\n' "$JULIA_THREADS"
  printf 'FULL_STATE_STORAGE=perlmutter_scratch\n'
  printf 'FULL_STATE_DIRECTORY=%s\n' "$state_directory"
  printf 'OPTIMIZER_CHECKPOINT_STORAGE=perlmutter_scratch\n'
  printf 'OPTIMIZER_CHECKPOINT_DIRECTORY=%s\n' "$checkpoint_directory"
  printf 'PRETIMEOUT_REQUEST_FILE=%s\n' "$pretimeout_request"
} >"$run_dir/worker.env"

{
  printf 'payload\tstorage_backend\tdirectory\tsync_policy\n'
  printf 'full_science_states\tperlmutter_scratch\t%s\texclude_from_routine_sync; retain until selected states are archived\n' "$state_directory"
  printf 'optimizer_checkpoints\tperlmutter_scratch\t%s\texclude_from_routine_sync; retain until continuation is complete\n' "$checkpoint_directory"
} >"$run_dir/scratch_storage.tsv"

cd "$project_root" || die "cannot enter project root"
set +e
srun --exact --exclusive --nodes=1 --ntasks=1 \
  --cpus-per-task="$SOLVER_STEP_CPUS" --cpu-bind=cores \
  /usr/bin/time -v -o "$run_dir/metrics/resource.time" \
  env PROJECT_B_PRETIMEOUT_REQUEST_FILE="$pretimeout_request" \
  PROJECT_B_OPTIMIZER_CHECKPOINT_DIRECTORY="$checkpoint_directory" \
  PROJECT_B_STATE_OUTPUT_DIRECTORY="$state_directory" \
  JULIA_NUM_THREADS="$JULIA_THREADS" JULIA_NUM_BLAS_THREADS=1 OMP_NUM_THREADS=1 \
  MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 BLIS_NUM_THREADS=1 \
  VECLIB_MAXIMUM_THREADS=1 ITENSOR_STRIDED_THREADS=1 \
  ITENSOR_THREADED_BLOCKSPARSE=true JULIA_PKG_PRECOMPILE_AUTO=0 \
  "$julia_bin" --startup-file=no --project="$project_root" \
  "$project_root/scripts/run_scan.jl" "$config_path" &
timed_step_pid=$!
while true; do
  wait "$timed_step_pid"
  wait_status=$?
  if kill -0 "$timed_step_pid" 2>/dev/null; then
    continue
  fi
  exit_code="$wait_status"
  break
done
trap - USR1

temporary_result="$run_dir/job.result.tmp.$$"
{
  printf 'job_id=%s\n' "$job_id"
  printf 'exit_code=%s\n' "$exit_code"
  printf 'scratch_package=%s\n' "$scratch_package"
  printf 'full_state_directory=%s\n' "$state_directory"
  printf 'optimizer_checkpoint_directory=%s\n' "$checkpoint_directory"
  if [[ -f "$pretimeout_request" ]]; then
    printf 'pretimeout_requested=true\n'
  else
    printf 'pretimeout_requested=false\n'
  fi
  printf 'finished_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$temporary_result"
mv "$temporary_result" "$run_dir/job.result"
exit "$exit_code"
