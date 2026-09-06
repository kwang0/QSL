#!/usr/bin/env bash

# Guarded operator launcher for the independent YC6-1 period-6 chi=512
# recovery. The literal `submit` action is complete authorization for one job.

set -euo pipefail

readonly LAUNCHER_VERSION="1.3.0"
readonly DEFAULT_ACCOUNT="m4863"
readonly DEFAULT_CONFIG_RELATIVE="configs/science_yc6_1_legacy_period6_chi512_tol1e4_after_p0p3375.toml"
readonly JOB_NAME="pb1-yc6r"
readonly ALLOCATION_CPUS=6
readonly SOLVER_STEP_CPUS=4
readonly JULIA_THREADS=2
readonly MEMORY="8G"
readonly TIME_LIMIT="48:00:00"
readonly QOS="shared"
readonly PRETIMEOUT_SIGNAL_SECONDS=3600
readonly SCRATCH_SUBDIRECTORY="QSL/project_b_flux_dimensional_reduction/phase1_vumps/yc6_1"
readonly FORECAST_NODE_HOURS="1.125000000"
readonly PRIOR_PHASE1_NODE_HOURS="14.865251736727779"
readonly PHASE1_CEILING_NODE_HOURS="20.0"
readonly PRIOR_PROJECT_NODE_HOURS="15.959684736727780"
readonly PROJECT_CEILING_NODE_HOURS="150.0"
readonly PRIOR_ACCOUNTING_NOTE="includes a conservative 1.125-node-hour reservation for the latest synced YC6 continuation pending its authoritative job ID and sacct row"

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
worker="$project_root/slurm/run_yc6_1_recovery_job.sh"
validator="$project_root/scripts/validate_yc6_1_recovery_config.jl"
run_root="$project_root/output/yc6_1_recovery_jobs"
julia_bin="${JULIA_BIN:-julia}"
phase1_account="${PHASE1_ACCOUNT:-$DEFAULT_ACCOUNT}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage:
  bash slurm/run_yc6_1_recovery_cpu.sh plan [CONFIG.toml]
  bash slurm/run_yc6_1_recovery_cpu.sh submit [CONFIG.toml]
  bash slurm/run_yc6_1_recovery_cpu.sh status [JOB_ID]
  bash slurm/run_yc6_1_recovery_cpu.sh reconcile [JOB_ID]

With no CONFIG argument, plan and submit use the exploratory 1e-4 VUMPS
residual profile, restarting theta/pi=0.35 from the immutable stricter-profile
accepted theta/pi=0.3375 state. `submit` authorizes one guarded Slurm mutation.
There is no automatic promotion or cancellation action.
EOF
  exit 2
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

is_perlmutter=false
if [[ "$(hostname -f 2>/dev/null || hostname)" == *perlmutter* ]]; then
  is_perlmutter=true
fi

require_perlmutter() {
  [[ "$is_perlmutter" == true ]] || die "$1 is authoritative only on Perlmutter"
}

resolve_scratch_root() {
  local scratch_root="${PSCRATCH:-${SCRATCH:-}}"
  [[ -n "$scratch_root" ]] || die 'neither PSCRATCH nor SCRATCH is defined'
  scratch_root="${scratch_root%/}"
  [[ "$scratch_root" == /pscratch/* ]] || die "unexpected scratch root: $scratch_root"
  [[ -d "$scratch_root" ]] || die "scratch root is unavailable: $scratch_root"
  printf '%s\n' "$scratch_root"
}

resolve_config() {
  local requested="${1:-$project_root/$DEFAULT_CONFIG_RELATIVE}"
  [[ -f "$requested" ]] || die "missing configuration: $requested"
  (cd "$(dirname "$requested")" && printf '%s/%s\n' "$PWD" "$(basename "$requested")")
}

validate_config() {
  local config_path="$1"
  command -v "$julia_bin" >/dev/null 2>&1 || die "Julia is unavailable: $julia_bin"
  [[ -f "$validator" ]] || die "missing recovery validator: $validator"
  "$julia_bin" --startup-file=no --project="$project_root" "$validator" "$config_path"
}

run_worker_preflight() {
  local config_path="$1"
  local config_sha="$2"
  local temporary_directory
  temporary_directory="$(mktemp -d)"
  if ! bash "$worker" "$project_root" "$config_path" "$config_sha" \
      "$temporary_directory" "$julia_bin" --preflight; then
    rm -rf "$temporary_directory"
    die "batch worker preflight failed"
  fi
  rm -rf "$temporary_directory"
}

projected_total() {
  awk -v prior="$1" -v forecast="$FORECAST_NODE_HOURS" \
    'BEGIN { printf "%.9f", prior + forecast }'
}

verify_budget() {
  local phase1_projected project_projected
  phase1_projected="$(projected_total "$PRIOR_PHASE1_NODE_HOURS")"
  project_projected="$(projected_total "$PRIOR_PROJECT_NODE_HOURS")"
  awk -v value="$phase1_projected" -v ceiling="$PHASE1_CEILING_NODE_HOURS" \
    'BEGIN { exit !(value <= ceiling) }' ||
    die "Phase 1 projected charge $phase1_projected exceeds $PHASE1_CEILING_NODE_HOURS"
  awk -v value="$project_projected" -v ceiling="$PROJECT_CEILING_NODE_HOURS" \
    'BEGIN { exit !(value <= ceiling) }' ||
    die "Project B projected charge $project_projected exceeds $PROJECT_CEILING_NODE_HOURS"
}

active_project_jobs() {
  local rows
  rows="$(squeue -h -u "$USER" -o '%A|%j')"
  awk -F '|' '$2 ~ /^(pb[0-4]-|project-b-)/ {print}' <<<"$rows"
}

verify_live_submission_state() {
  require_perlmutter submit
  command -v sbatch >/dev/null 2>&1 || die "sbatch is unavailable"
  command -v squeue >/dev/null 2>&1 || die "squeue is unavailable"
  resolve_scratch_root >/dev/null
  local active
  active="$(active_project_jobs)"
  [[ -z "$active" ]] || die "another Project B job is active: $active"
}

verify_clean_target() {
  local output_directory="$1"
  local existing=""
  if [[ -d "$output_directory" ]]; then
    existing="$(find "$output_directory" -type f \
      \( -name 'state_*.h5' -o -name 'checkpoint_*.h5' \
      -o -name 'resume_from_checkpoint_*.toml' \
      -o -name 'scan_outcome.toml' -o -name 'pretimeout_outcome.toml' \) \
      -print -quit)"
  fi
  [[ -z "$existing" ]] ||
    die "recovery output already contains immutable scientific artifacts; use its generated checkpoint-resume configuration instead of duplicating the run: $existing"
}

print_plan() {
  local action="$1"
  local config_path="$2"
  local validation="$3"
  local config_sha output branch preparation chi residual_tol max_iterations fluxes minimum_step minimum_overlap startup_source checkpoint_cadence scratch_display
  IFS=$'\t' read -r config_sha output branch preparation chi residual_tol max_iterations \
    fluxes minimum_step minimum_overlap startup_source checkpoint_cadence <<<"$validation"
  if [[ "$is_perlmutter" == true ]]; then
    scratch_display="$(resolve_scratch_root)/$SCRATCH_SUBDIRECTORY/job_<slurm-job-id>_${config_sha:0:12}/optimizer_checkpoints"
  else
    scratch_display="\$PSCRATCH/$SCRATCH_SUBDIRECTORY/job_<slurm-job-id>_${config_sha:0:12}/optimizer_checkpoints"
  fi
  verify_budget
  cat <<EOF
Project B YC6-1 legacy-supercell recovery plan
  operator action: $action
  launcher version: $LAUNCHER_VERSION
  configuration: $config_path
  configuration SHA-256: $config_sha
  geometry: YC6-1; U(1); uniform twist gauge; MPS period 6
  branch: $branch
  preparation: $preparation
  chi / VUMPS residual target: $chi / $residual_tol
  outer-iteration cap: $max_iterations
  nominal flux grid: $fluxes
  startup source: $startup_source
  adaptive bisection floor: $minimum_step pi
  parent-overlap floor: $minimum_overlap per site (broad trust-region guard, not a physical cutoff)
  optimizer checkpoints: every $checkpoint_cadence completed target-chi outer iterations and after each growth stage
  optimizer checkpoint storage: $scratch_display (temporary; excluded from routine sync)
  project-side checkpoint payload: compact hash-pinned resume TOMLs only
  Slurm pre-timeout signal: USR1 to batch shell $PRETIMEOUT_SIGNAL_SECONDS seconds before time limit
  resources: allocation-logical-cpus=$ALLOCATION_CPUS solver-step-logical-cpus=$SOLVER_STEP_CPUS julia-threads=$JULIA_THREADS memory=$MEMORY qos=$QOS time=$TIME_LIMIT
  worst-case charge: $FORECAST_NODE_HOURS node-hours
  Phase 1 budget: prior=$PRIOR_PHASE1_NODE_HOURS projected=$(projected_total "$PRIOR_PHASE1_NODE_HOURS") ceiling=$PHASE1_CEILING_NODE_HOURS
  Project B budget: prior=$PRIOR_PROJECT_NODE_HOURS projected=$(projected_total "$PRIOR_PROJECT_NODE_HOURS") ceiling=$PROJECT_CEILING_NODE_HOURS
  prior accounting note: $PRIOR_ACCOUNTING_NOTE
  output: $output
  accepted YC8-1 lineage parent changed: no
  automatic submission/advance: disabled
EOF
  if [[ "$is_perlmutter" == true ]]; then
    command -v squeue >/dev/null 2>&1 || die "squeue is unavailable"
    local active
    active="$(active_project_jobs)"
    [[ -z "$active" ]] || die "another Project B job is active: $active"
    printf '  accounting authority: live Perlmutter one-job check passed\n'
  else
    printf '  accounting authority: LOCAL STRUCTURAL PLAN ONLY; Perlmutter state not verified\n'
  fi
  verify_clean_target "$output"
}

resolve_run_dir() {
  local requested_job_id="${1:-}"
  local best_dir="" best_job_id=-1 job_file candidate_job_id
  [[ -d "$run_root" ]] || die "no YC6-1 recovery submissions are recorded"
  while IFS= read -r job_file; do
    candidate_job_id="$(awk -F '\t' 'NR == 2 {print $1}' "$job_file")"
    [[ "$candidate_job_id" =~ ^[0-9]+$ ]] || continue
    if [[ -n "$requested_job_id" ]]; then
      if [[ "$candidate_job_id" == "$requested_job_id" ]]; then
        dirname "$job_file"
        return 0
      fi
    elif (( candidate_job_id > best_job_id )); then
      best_job_id="$candidate_job_id"
      best_dir="$(dirname "$job_file")"
    fi
  done < <(find "$run_root" -mindepth 2 -maxdepth 2 -type f -name job.tsv | sort)
  if [[ -n "$requested_job_id" ]]; then
    die "no recovery package records job $requested_job_id"
  fi
  [[ -n "$best_dir" ]] || die "no recovery job record is available"
  printf '%s\n' "$best_dir"
}

resolve_job_id() {
  local run_dir="$1"
  local job_id
  job_id="$(awk -F '\t' 'NR == 2 {print $1}' "$run_dir/job.tsv")"
  [[ "$job_id" =~ ^[0-9]+$ ]] || die "invalid job record in $run_dir/job.tsv"
  printf '%s\n' "$job_id"
}

[[ $# -ge 1 ]] || usage
command_name="$1"
shift

case "$command_name" in
  plan|submit)
    [[ $# -le 1 ]] || usage
    config_path="$(resolve_config "${1:-}")"
    validation="$(validate_config "$config_path")"
    IFS=$'\t' read -r config_sha output branch preparation chi residual_tol max_iterations \
      fluxes minimum_step minimum_overlap startup_source checkpoint_cadence <<<"$validation"
    run_worker_preflight "$config_path" "$config_sha"
    print_plan "$command_name" "$config_path" "$validation"
    if [[ "$command_name" == submit ]]; then
      verify_live_submission_state
      verify_budget
      verify_clean_target "$output"
      [[ -f "$worker" ]] || die "missing batch worker: $worker"
      mkdir -p "$run_root"
      run_id="$(date -u +%Y%m%dT%H%M%SZ)-yc6-1-legacy-period6-chi512-tol1e4"
      run_dir="$run_root/$run_id"
      [[ ! -e "$run_dir" ]] || die "run package already exists: $run_dir"
      mkdir -p "$run_dir/logs" "$run_dir/metrics"
      cp "$config_path" "$run_dir/config.snapshot.toml"
      printf '%s\n' "$config_sha" >"$run_dir/config.sha256"
      printf '%s\n' "$FORECAST_NODE_HOURS" >"$run_dir/forecast_node_hours.txt"
      raw_job_id="$(sbatch --parsable --job-name="$JOB_NAME" \
        --account="$phase1_account" --constraint=cpu --qos="$QOS" \
        --licenses=scratch \
        --nodes=1 --ntasks=1 --cpus-per-task="$ALLOCATION_CPUS" \
        --mem="$MEMORY" --time="$TIME_LIMIT" --chdir="$project_root" \
        --signal="B:USR1@$PRETIMEOUT_SIGNAL_SECONDS" \
        --output="$run_dir/logs/scan-%j.out" --export=ALL \
        "$worker" "$project_root" "$config_path" "$config_sha" "$run_dir" "$julia_bin")"
      job_id="${raw_job_id%%;*}"
      [[ "$job_id" =~ ^[0-9]+$ ]] || die "Slurm returned an invalid job ID: $raw_job_id"
      printf 'job_id\tphase\tgeometry\tbranch\tchi\tconfig_sha256\tallocation_cpus\tsolver_step_cpus\tmemory\ttime_limit\tforecast_node_hours\tstartup_source\tcheckpoint_cadence\tpretimeout_signal_seconds\tcheckpoint_storage\n' >"$run_dir/job.tsv"
      printf '%s\t1\tYC6-1\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tperlmutter_scratch\n' \
        "$job_id" "$branch" "$chi" "$config_sha" "$ALLOCATION_CPUS" \
        "$SOLVER_STEP_CPUS" "$MEMORY" "$TIME_LIMIT" "$FORECAST_NODE_HOURS" \
        "$startup_source" "$checkpoint_cadence" "$PRETIMEOUT_SIGNAL_SECONDS" \
        >>"$run_dir/job.tsv"
      printf '%s\n' "$run_dir" >"$run_root/latest_run.txt"
      printf 'Slurm accepted YC6-1 recovery job %s.\n' "$job_id"
      printf 'Run package: %s\n' "$run_dir"
      printf 'Next command: bash slurm/run_yc6_1_recovery_cpu.sh status\n'
    fi
    ;;
  status)
    [[ $# -le 1 ]] || usage
    require_perlmutter status
    requested_job_id="${1:-}"
    [[ -z "$requested_job_id" || "$requested_job_id" =~ ^[0-9]+$ ]] || die "invalid job ID"
    run_dir="$(resolve_run_dir "$requested_job_id")"
    job_id="$(resolve_job_id "$run_dir")"
    squeue -j "$job_id" -o '%.18i %.12T %.10M %.10l %.6D %.6C %R' || true
    sacct -j "$job_id" --starttime=2026-08-01 \
      --format=JobIDRaw,JobName,State,Elapsed,Timelimit,NNodes,NCPUS,ExitCode,MaxRSS,AveRSS,ReqMem -X
    ;;
  reconcile)
    [[ $# -le 1 ]] || usage
    require_perlmutter reconcile
    requested_job_id="${1:-}"
    [[ -z "$requested_job_id" || "$requested_job_id" =~ ^[0-9]+$ ]] || die "invalid job ID"
    run_dir="$(resolve_run_dir "$requested_job_id")"
    job_id="$(resolve_job_id "$run_dir")"
    reconciliation="$run_dir/sacct.tsv"
    [[ ! -e "$reconciliation" ]] || die "refusing to overwrite $reconciliation"
    temporary="$reconciliation.tmp"
    sacct -j "$job_id" --starttime=2026-08-01 -n -P \
      --format=JobIDRaw,JobName,State,ElapsedRaw,TimelimitRaw,NNodes,NCPUS,ExitCode,MaxRSS,AveRSS,ReqMem -X \
      >"$temporary"
    [[ -s "$temporary" ]] || die "Perlmutter accounting has not populated for job $job_id"
    job_state="$(awk -F '|' -v job_id="$job_id" '$1 == job_id {print $3; exit}' "$temporary")"
    elapsed_seconds="$(awk -F '|' -v job_id="$job_id" '$1 == job_id {print $4; exit}' "$temporary")"
    [[ -n "$job_state" ]] || die "accounting has no exact record for job $job_id"
    normalized_state="${job_state%% *}"
    normalized_state="${normalized_state%%+*}"
    case "$normalized_state" in
      COMPLETED|FAILED|CANCELLED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|PREEMPTED|BOOT_FAIL|DEADLINE|REVOKED|SPECIAL_EXIT) ;;
      *) rm -f "$temporary"; die "job $job_id is not terminal (state $job_state)" ;;
    esac
    [[ "$elapsed_seconds" =~ ^[0-9]+$ ]] || die "invalid elapsed time in accounting"
    mv "$temporary" "$reconciliation"
    awk -v seconds="$elapsed_seconds" 'BEGIN {printf "%.9f\n", seconds / 3600.0 * 3.0 / 128.0}' \
      >"$run_dir/charged_node_hours.txt"
    printf 'Reconciled terminal job %s (%s): %s\n' "$job_id" "$job_state" "$reconciliation"
    printf 'Recorded charged node-hours: %s\n' "$(tr -d '[:space:]' <"$run_dir/charged_node_hours.txt")"
    ;;
  *)
    usage
    ;;
esac
