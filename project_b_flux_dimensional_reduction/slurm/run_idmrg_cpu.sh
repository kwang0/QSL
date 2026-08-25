#!/usr/bin/env bash
set -euo pipefail

# Guarded Phase 1 iDMRG operator launcher. The literal `submit` command is the
# complete authorization for one scheduler-mutating action.

readonly DEFAULT_ACCOUNT="m4863"
readonly ACTIVE_CONTROL_REF="configs/phase1_idmrg_active_control.ref"
readonly WORKING_CONVERGENCE_POLICY="configs/phase1_idmrg_working_convergence.toml"
readonly ACCEPTED_PARENT_RELATIVE="output/phase1_tests/yc8_1/parallel_update_p0p10000000_to_p0p15000000_chi512_f71fc084883e_b5ef48caaf7a/chi512/states/state_0001_yc8-1_primary_forward_chi512_legacy_0p1_independent_theta0_alternating_chi512_forward_seed101_chi512_theta_p0p15000000_accepted_aca60c183c9d.h5"

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
julia_bin="${JULIA_BIN:-julia}"
phase1_account="${PHASE1_ACCOUNT:-$DEFAULT_ACCOUNT}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage:
  bash slurm/run_idmrg_cpu.sh plan [CONTROL.toml]
  bash slurm/run_idmrg_cpu.sh submit [CONTROL.toml]
  bash slurm/run_idmrg_cpu.sh status [CONTROL.toml] [JOB_ID]
  bash slurm/run_idmrg_cpu.sh reconcile [CONTROL.toml] [JOB_ID]
  bash slurm/run_idmrg_cpu.sh analyze [CONTROL.toml]
  bash slurm/run_idmrg_cpu.sh analyze-working [CONTROL.toml]

With no CONTROL argument, the launcher uses the hash-pinned control named by
configs/phase1_idmrg_active_control.ref. `submit` is the complete, explicit
authorization for one guarded Slurm submission; no acknowledgement variable
is required. The default NERSC account is m4863 and PHASE1_ACCOUNT may override
it. A successful submit records the job ID, so status and reconcile need no
JOB_ID. Analyze runs locally after the package has been copied back by Globus.
Analyze-working applies the separately pinned owner-selected working policy
without rewriting the source control or its original analysis. There is no
automatic submission or automatic advance.
EOF
  exit 2
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

is_perlmutter=false
if [[ "$(hostname -f 2>/dev/null || hostname)" == *perlmutter* ]]; then
  is_perlmutter=true
fi

require_perlmutter() {
  [[ "$is_perlmutter" == true ]] || die "$1 is authoritative only on Perlmutter"
}

resolve_control() {
  local requested="${1:-}"
  local ref_path="$project_root/$ACTIVE_CONTROL_REF"
  local expected_sha=""
  if [[ -z "$requested" ]]; then
    [[ -f "$ref_path" ]] || die "missing active-control reference: $ref_path"
    requested="$(sed -n '1p' "$ref_path")"
    expected_sha="$(sed -n '2p' "$ref_path")"
    [[ "$requested" == output/phase1_idmrg/* ]] ||
      die "active-control reference has an unsafe path: $requested"
    [[ "$requested" != *..* ]] ||
      die "active-control reference may not contain '..'"
    [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] ||
      die "active-control reference has an invalid SHA-256"
    requested="$project_root/$requested"
  fi
  [[ -f "$requested" ]] || die "missing control: $requested"
  local resolved
  resolved="$(cd "$(dirname "$requested")" && pwd)/$(basename "$requested")"
  if [[ -n "$expected_sha" ]]; then
    [[ "$(sha256_file "$resolved")" == "$expected_sha" ]] ||
      die "active control SHA-256 does not match $ref_path"
  fi
  printf '%s\n' "$resolved"
}

parse_control_and_job_arguments() {
  control_argument=""
  job_id_argument=""
  case "$command_name" in
    plan|submit|analyze|analyze-working)
      [[ $# -le 1 ]] || usage
      control_argument="${1:-}"
      ;;
    status|reconcile)
      [[ $# -le 2 ]] || usage
      if [[ $# -ge 1 && "$1" =~ ^[0-9]+$ ]]; then
        job_id_argument="$1"
        [[ $# -eq 1 ]] || usage
      else
        control_argument="${1:-}"
        job_id_argument="${2:-}"
      fi
      ;;
    *)
      usage
      ;;
  esac
}

[[ $# -ge 1 ]] || usage
command_name="$1"
shift

parse_control_and_job_arguments "$@"
control_path="$(resolve_control "$control_argument")"
[[ -f "$project_root/idmrg/Manifest.toml" ]] || die "missing pinned iDMRG Manifest.toml"
command -v "$julia_bin" >/dev/null 2>&1 || die "Julia is unavailable: $julia_bin"
[[ "$phase1_account" =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid PHASE1_ACCOUNT"

case "$command_name" in
  submit|status|reconcile)
    require_perlmutter "$command_name"
    ;;
  analyze|analyze-working)
    [[ "$is_perlmutter" != true ]] ||
      die "analyze is a local post-sync command; do not run it on a Perlmutter login node"
    ;;
esac

validator_arguments=("$control_path")
if [[ "$command_name" == analyze || "$command_name" == analyze-working ]]; then
  validator_arguments+=(--postprocess)
fi
validation="$($julia_bin --startup-file=no --project="$project_root/idmrg" \
  "$project_root/idmrg/scripts/validate_control.jl" "${validator_arguments[@]}")"
IFS=$'\t' read -r control_sha bridge_sha parent_path parent_sha seed_path seed_sha \
  result_path lightweight_path storage_backend scratch_subdirectory checkpoint_leaf \
  parent_theta target_theta nodes cpus julia_threads memory time_limit qos \
  maximum_new_node_hours maximum_jobs \
  prior_phase1_node_hours phase1_ceiling_node_hours prior_project_node_hours \
  project_ceiling_node_hours previous_sacct_path previous_sacct_sha previous_job_id \
  <<<"$validation"
[[ "$control_sha" =~ ^[0-9a-f]{64}$ ]] || die "validator returned an invalid control hash"
[[ "$bridge_sha" =~ ^[0-9a-f]{64}$ ]] || die "validator returned an invalid bridge hash"
[[ "$maximum_jobs" == 1 ]] || die "validator did not preserve the one-job guard"
manifest_sha="$(sha256_file "$project_root/idmrg/Manifest.toml")"
package_directory="$(dirname "$result_path")"
job_id_file="$package_directory/job_id.txt"

checkpoint_directory="$checkpoint_leaf"
if [[ "$storage_backend" == perlmutter_scratch ]]; then
  [[ "$scratch_subdirectory" != /* ]] || die "scratch subdirectory must be relative"
  [[ "$scratch_subdirectory" != *..* ]] || die "scratch subdirectory may not contain '..'"
  if [[ "$is_perlmutter" == true ]]; then
    scratch_root="${PSCRATCH:-${SCRATCH:-}}"
    [[ -n "$scratch_root" ]] || die 'neither PSCRATCH nor SCRATCH is defined'
    scratch_root="${scratch_root%/}"
    [[ "$scratch_root" == /pscratch/* ]] || die "unexpected scratch root: $scratch_root"
    checkpoint_directory="$scratch_root/$scratch_subdirectory/$checkpoint_leaf"
  else
    checkpoint_directory="\$PSCRATCH/$scratch_subdirectory/$checkpoint_leaf"
  fi
elif [[ "$storage_backend" != package_directory ]]; then
  die "unsupported storage backend: $storage_backend"
fi

verify_file_hash() {
  local label="$1"
  local path="$2"
  local expected="$3"
  [[ -f "$path" ]] || die "missing $label on Perlmutter: $path"
  local actual
  actual="$(sha256_file "$path")"
  [[ "$actual" == "$expected" ]] || die "$label SHA-256 mismatch"
}

verify_authoritative_inputs() {
  verify_file_hash "accepted parent" "$parent_path" "$parent_sha"
  if [[ "$seed_sha" != "$parent_sha" || "$seed_path" != "$parent_path" ]]; then
    verify_file_hash "rejected numerical seed" "$seed_path" "$seed_sha"
  fi
  if [[ "$previous_sacct_path" != none ]]; then
    verify_file_hash "prior sacct evidence" "$previous_sacct_path" "$previous_sacct_sha"
  fi
}

verify_submission_targets() {
  [[ ! -e "$job_id_file" ]] ||
    die "this control already recorded a submitted job: $job_id_file"
  [[ ! -e "$result_path" ]] || die "refusing to overwrite result: $result_path"
  if [[ "$lightweight_path" != none ]]; then
    [[ ! -e "$lightweight_path" ]] ||
      die "refusing to overwrite lightweight archive: $lightweight_path"
  fi
  if [[ -d "$checkpoint_directory" ]]; then
    [[ -z "$(find "$checkpoint_directory" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
      die "checkpoint directory is not empty: $checkpoint_directory"
  elif [[ -e "$checkpoint_directory" ]]; then
    die "checkpoint path exists but is not a directory: $checkpoint_directory"
  fi
}

print_plan() {
  local action="$1"
  cat <<EOF
Project B Phase 1 one-point iDMRG plan
  operator action: $action
  control: $control_path
  control SHA-256: $control_sha
  bridge SHA-256: $bridge_sha
  iDMRG Manifest SHA-256: $manifest_sha
  immutable accepted parent SHA-256: $parent_sha
  numerical seed SHA-256: $seed_sha
  numerical seed status: $([[ "$seed_sha" == "$parent_sha" ]] && printf 'accepted lineage parent' || printf 'rejected/nonconverged; not the lineage parent')
  step: theta/pi=$parent_theta -> $target_theta
  target: YC8-1, period 2, U(1), uniform gauge, chi 512
  solver: MPSKit 0.13.13 one-site IDMRG
  account: $phase1_account
  resources: nodes=$nodes cpus-per-task=$cpus julia-threads=$julia_threads memory=$memory qos=$qos time=$time_limit
  maximum forecast charge: $maximum_new_node_hours node-hours; maximum new jobs: $maximum_jobs
  Phase 1 budget: prior=$prior_phase1_node_hours ceiling=$phase1_ceiling_node_hours node-hours
  project budget: prior=$prior_project_node_hours ceiling=$project_ceiling_node_hours node-hours
  result: $result_path
  lightweight home archive: $lightweight_path
  heavy checkpoints: $checkpoint_directory
  storage backend: $storage_backend
  startup source: immutable bridge only; no prior checkpoint
  job 57452187 checkpoints required: no
  submission authorization: literal submit command
  automatic submission/advance: disabled
EOF
  if [[ "$previous_job_id" != none ]]; then
    printf '  reconciled predecessor job: %s (%s)\n' "$previous_job_id" "$previous_sacct_path"
  fi
  verify_submission_targets
  if [[ "$is_perlmutter" == true ]]; then
    verify_authoritative_inputs
    command -v squeue >/dev/null || die "squeue is unavailable"
    active="$(squeue -h -u "$USER" -n pb1-idmrg -o '%A' | wc -l | tr -d ' ')"
    [[ "$active" == 0 ]] || die "an active pb1-idmrg job already consumes the one-job budget"
    printf '  accounting authority: live Perlmutter checks passed\n'
  else
    printf '  accounting authority: LOCAL STRUCTURAL PLAN ONLY; Perlmutter state not verified\n'
  fi
}

resolve_job_id() {
  local requested="${1:-}"
  if [[ -z "$requested" ]]; then
    [[ -f "$job_id_file" ]] ||
      die "missing recorded job ID: run submit first or pass JOB_ID explicitly"
    requested="$(tr -d '[:space:]' <"$job_id_file")"
  fi
  [[ "$requested" =~ ^[0-9]+$ ]] || die "invalid job id: $requested"
  printf '%s\n' "$requested"
}

case "$command_name" in
  plan)
    print_plan plan
    ;;
  submit)
    print_plan submit
    mkdir -p "$package_directory/logs" "$checkpoint_directory"
    sbatch_args=(
      --parsable
      --job-name=pb1-idmrg
      --account="$phase1_account"
      --constraint=cpu
      --qos="$qos"
      --nodes="$nodes"
      --ntasks=1
      --cpus-per-task="$cpus"
      --mem="$memory"
      --time="$time_limit"
      --output="$package_directory/logs/idmrg-%j.out"
      --export="ALL,PROJECT_B_IDMRG_CHECKPOINT_DIRECTORY=$checkpoint_directory"
    )
    if [[ "$storage_backend" == perlmutter_scratch ]]; then
      sbatch_args+=(--licenses=scratch)
    fi
    raw_job_id="$(sbatch "${sbatch_args[@]}" \
      --wrap="srun --cpu-bind=cores env JULIA_NUM_THREADS=$julia_threads OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 $julia_bin --startup-file=no --project=$project_root/idmrg $project_root/idmrg/scripts/run_idmrg.jl $control_path $result_path")"
    job_id="${raw_job_id%%;*}"
    [[ "$job_id" =~ ^[0-9]+$ ]] || die "Slurm returned an invalid job ID: $raw_job_id"
    printf 'Slurm accepted job %s.\n' "$job_id"
    temporary_job_id_file="$job_id_file.tmp.$$"
    printf '%s\n' "$job_id" >"$temporary_job_id_file"
    mv "$temporary_job_id_file" "$job_id_file"
    printf 'Recorded job ID: %s\n' "$job_id_file"
    printf 'Next command: bash slurm/run_idmrg_cpu.sh status\n'
    ;;
  status)
    job_id="$(resolve_job_id "$job_id_argument")"
    squeue -j "$job_id" -o '%.18i %.12T %.10M %.10l %.6D %.6C %R' || true
    sacct -j "$job_id" --starttime=2026-08-01 \
      --format=JobIDRaw,JobName,State,Elapsed,Timelimit,NNodes,NCPUS,ExitCode -X
    ;;
  reconcile)
    job_id="$(resolve_job_id "$job_id_argument")"
    reconciliation="$package_directory/sacct-${job_id}.tsv"
    [[ ! -e "$reconciliation" ]] || die "refusing to overwrite reconciliation: $reconciliation"
    temporary="$reconciliation.tmp"
    sacct -j "$job_id" --starttime=2026-08-01 -n -P \
      --format=JobIDRaw,JobName,State,ElapsedRaw,TimelimitRaw,NNodes,NCPUS,ExitCode -X \
      >"$temporary"
    [[ -s "$temporary" ]] || die "Perlmutter accounting has not populated for job $job_id"
    job_state="$(awk -F '|' -v job_id="$job_id" '$1 == job_id { print $3; exit }' "$temporary")"
    [[ -n "$job_state" ]] || die "Perlmutter accounting has no exact record for job $job_id"
    normalized_job_state="${job_state%% *}"
    normalized_job_state="${normalized_job_state%%+*}"
    case "$normalized_job_state" in
      COMPLETED|FAILED|CANCELLED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|PREEMPTED|BOOT_FAIL|DEADLINE|REVOKED|SPECIAL_EXIT)
        ;;
      *)
        rm -f "$temporary"
        die "job $job_id is not terminal (state $job_state); run status and wait"
        ;;
    esac
    mv "$temporary" "$reconciliation"
    printf 'Reconciled terminal job %s (%s): %s\n' \
      "$job_id" "$job_state" "$reconciliation"
    ;;
  analyze)
    [[ -f "$result_path" ]] ||
      die "missing synced result: $result_path; copy the run package back with Globus first"
    local_parent="$project_root/$ACCEPTED_PARENT_RELATIVE"
    analysis_directory="$package_directory/analysis"
    "$julia_bin" --startup-file=no --project="$project_root" \
      "$project_root/scripts/analyze_phase1_idmrg_result.jl" \
      "$result_path" "$local_parent" "$analysis_directory"
    ;;
  analyze-working)
    [[ -f "$result_path" ]] ||
      die "missing synced result: $result_path; copy the run package back with Globus first"
    local_parent="$project_root/$ACCEPTED_PARENT_RELATIVE"
    working_policy="$project_root/$WORKING_CONVERGENCE_POLICY"
    [[ -f "$working_policy" ]] ||
      die "missing working convergence policy: $working_policy"
    analysis_directory="$package_directory/analysis"
    "$julia_bin" --startup-file=no --project="$project_root" \
      "$project_root/scripts/analyze_phase1_idmrg_result.jl" \
      "$result_path" "$local_parent" "$analysis_directory" "$working_policy"
    ;;
esac
