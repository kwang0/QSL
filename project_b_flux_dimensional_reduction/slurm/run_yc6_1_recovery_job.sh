#!/usr/bin/env bash

# Batch worker for the YC6-1 legacy-supercell recovery. Slurm may execute this
# file from a spool directory, so every repository path is supplied explicitly.

set -u

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

[[ -f "$project_root/Project.toml" ]] || die "missing Project.toml under $project_root"
[[ -f "$project_root/scripts/run_scan.jl" ]] || die "missing scan driver under $project_root"
[[ -f "$project_root/scripts/validate_yc6_1_recovery_config.jl" ]] ||
  die "missing recovery validator under $project_root"
[[ -f "$config_path" ]] || die "missing recovery configuration: $config_path"
[[ "$(sha256_file "$config_path")" == "$expected_config_sha256" ]] ||
  die "configuration SHA-256 changed after submission"
command -v "$julia_bin" >/dev/null 2>&1 || die "Julia is unavailable: $julia_bin"

mkdir -p "$run_dir"
"$julia_bin" --startup-file=no --project="$project_root" \
  "$project_root/scripts/validate_yc6_1_recovery_config.jl" "$config_path" \
  >"$run_dir/worker-preflight.tsv"

if [[ "$preflight" == true ]]; then
  printf 'YC6-1 recovery worker preflight passed.\n'
  exit 0
fi

command -v srun >/dev/null 2>&1 || die "srun is unavailable"
[[ -x /usr/bin/time ]] || die "/usr/bin/time is unavailable"

allocation_cpus="${SLURM_CPUS_PER_TASK:-0}"
[[ "$allocation_cpus" =~ ^[1-9][0-9]*$ ]] ||
  die "invalid SLURM_CPUS_PER_TASK=$allocation_cpus"
(( allocation_cpus == 6 )) ||
  die "the recovery allocation needs at least six logical CPUs"

job_id="${SLURM_JOB_ID:-}"
[[ "$job_id" =~ ^[1-9][0-9]*$ ]] || die "invalid or missing SLURM_JOB_ID=$job_id"
scratch_root="${PSCRATCH:-${SCRATCH:-}}"
[[ -n "$scratch_root" ]] || die 'neither PSCRATCH nor SCRATCH is defined'
scratch_root="${scratch_root%/}"
[[ "$scratch_root" == /pscratch/* ]] || die "unexpected scratch root: $scratch_root"
[[ -d "$scratch_root" ]] || die "scratch root is unavailable: $scratch_root"
checkpoint_directory="$scratch_root/QSL/project_b_flux_dimensional_reduction/phase1_vumps/yc6_1/job_${job_id}_${expected_config_sha256:0:12}/optimizer_checkpoints"
[[ ! -e "$checkpoint_directory" ]] ||
  die "scratch checkpoint directory already exists: $checkpoint_directory"
mkdir -p "$checkpoint_directory"

mkdir -p "$run_dir/metrics"
pretimeout_request="$run_dir/pretimeout.request"
[[ ! -e "$pretimeout_request" ]] || die "stale pre-timeout request exists: $pretimeout_request"

handle_pretimeout() {
  [[ ! -e "$pretimeout_request" ]] || return 0
  local temporary_request="$pretimeout_request.tmp.$$"
  {
    printf 'requested_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'job_id=%s\n' "${SLURM_JOB_ID:-unknown}"
    printf 'signal=USR1\n'
  } >"$temporary_request"
  mv "$temporary_request" "$pretimeout_request"
  printf 'Slurm pre-timeout signal recorded at %s; Julia will checkpoint after its current outer iteration.\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

trap handle_pretimeout USR1
{
  printf 'PROJECT_ROOT=%s\n' "$project_root"
  printf 'CONFIG_PATH=%s\n' "$config_path"
  printf 'CONFIG_SHA256=%s\n' "$expected_config_sha256"
  printf 'SLURM_JOB_ID=%s\n' "${SLURM_JOB_ID:-unset}"
  printf 'SLURM_CPUS_PER_TASK=%s\n' "$allocation_cpus"
  printf 'SOLVER_STEP_CPUS=4\n'
  printf 'JULIA_THREADS=2\n'
  printf 'OPTIMIZER_CHECKPOINT_STORAGE=perlmutter_scratch\n'
  printf 'OPTIMIZER_CHECKPOINT_DIRECTORY=%s\n' "$checkpoint_directory"
  printf 'PRETIMEOUT_REQUEST_FILE=%s\n' "$pretimeout_request"
} >"$run_dir/worker.env"

{
  printf 'storage_backend\tcheckpoint_directory\tsync_policy\n'
  printf 'perlmutter_scratch\t%s\texclude_from_routine_globus_sync\n' \
    "$checkpoint_directory"
} >"$run_dir/checkpoint_storage.tsv"

cd "$project_root" || die "cannot enter project root"

set +e
srun --exact --exclusive --nodes=1 --ntasks=1 --cpus-per-task=4 --cpu-bind=cores \
  /usr/bin/time -v -o "$run_dir/metrics/resource.time" \
  env PROJECT_B_PRETIMEOUT_REQUEST_FILE="$pretimeout_request" \
  PROJECT_B_OPTIMIZER_CHECKPOINT_DIRECTORY="$checkpoint_directory" \
  JULIA_NUM_THREADS=2 JULIA_NUM_BLAS_THREADS=1 OMP_NUM_THREADS=1 \
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
set -e

temporary_result="$run_dir/job.result.tmp.$$"
{
  printf 'job_id=%s\n' "${SLURM_JOB_ID:-unknown}"
  printf 'exit_code=%s\n' "$exit_code"
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
