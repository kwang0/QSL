#!/usr/bin/env bash

# Guarded operator launcher for the YC8-1 chi=1024 fixed-theta-growth and
# short-flux-bridge campaign. The literal `submit` action authorizes one job.

set -euo pipefail

readonly LAUNCHER_VERSION="1.1.0"
readonly DEFAULT_ACCOUNT="m4863"
readonly DEFAULT_CONFIG_RELATIVE="configs/science_yc8_1_primary_forward_chi1024_bridge.toml"
readonly JOB_NAME="pb1-yc8b"
readonly ALLOCATION_CPUS=18
readonly SOLVER_STEP_CPUS=8
readonly JULIA_THREADS=4
readonly MEMORY="32G"
readonly TIME_LIMIT="48:00:00"
readonly QOS="shared"
readonly PRETIMEOUT_SIGNAL_SECONDS=7200
readonly SCRATCH_SUBDIRECTORY="QSL/project_b_flux_dimensional_reduction/phase1_vumps/yc8_1"
readonly FORECAST_NODE_HOURS="3.375000000"
readonly PHASE1_CEILING_NODE_HOURS="20.0"
readonly PROJECT_CEILING_NODE_HOURS="150.0"

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/slurm/lib/project_b_resources.sh"
worker="$project_root/slurm/run_yc8_1_chi1024_bridge_job.sh"
validator="$project_root/scripts/validate_yc8_1_chi1024_bridge_config.jl"
run_root="$project_root/output/yc8_1_chi1024_bridge_jobs"
julia_bin="${JULIA_BIN:-julia}"
phase1_account="${PHASE1_ACCOUNT:-$DEFAULT_ACCOUNT}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage:
  bash slurm/run_yc8_1_chi1024_bridge_cpu.sh plan [CONFIG.toml]
  bash slurm/run_yc8_1_chi1024_bridge_cpu.sh submit [CONFIG.toml]
  bash slurm/run_yc8_1_chi1024_bridge_cpu.sh status [JOB_ID]
  bash slurm/run_yc8_1_chi1024_bridge_cpu.sh reconcile [JOB_ID]

The default control grows the immutable accepted theta/pi=0.15 YC8-1 state
from chi=512 to chi=1024 at fixed theta, then advances to theta/pi=0.45 on a
0.025 grid with adaptive bisection. Full states and optimizer checkpoints are
kept in PSCRATCH; compact manifests and job evidence stay in the project.
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
  [[ -f "$validator" ]] || die "missing bridge validator: $validator"
  "$julia_bin" --startup-file=no --project="$project_root" "$validator" "$config_path"
}

run_worker_preflight() {
  local config_path="$1"
  local config_sha="$2"
  local temporary_directory
  temporary_directory="$(mktemp -d)"
  cp "$worker" "$temporary_directory/worker.sh"
  if ! bash "$temporary_directory/worker.sh" "$project_root" "$config_path" "$config_sha" \
      "$temporary_directory" "$julia_bin" --preflight; then
    rm -rf "$temporary_directory"
    die "batch worker preflight failed"
  fi
  rm -rf "$temporary_directory"
}

verify_budget() {
  local authority=local
  [[ "$is_perlmutter" != true ]] || authority=live
  local allocated forecast
  IFS=$'\t' read -r allocated forecast <<<"$(pb_forecast "$project_root" "$ALLOCATION_CPUS" "$MEMORY" "$TIME_LIMIT" "$QOS")"
  [[ "$allocated" == "$ALLOCATION_CPUS" ]] || die "allocation forecast changed"
  pb_guard "$project_root" "$forecast" "$authority"
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
      \( -name 'state_*.h5' -o -name 'state_*.toml' \
      -o -name 'resume_from_checkpoint_*.toml' \
      -o -name 'scan_outcome.toml' -o -name 'pretimeout_outcome.toml' \) \
      -print -quit)"
  fi
  [[ -z "$existing" ]] || die "bridge output already contains immutable artifacts: $existing"
}

print_plan() {
  local action="$1"
  local config_path="$2"
  local validation="$3"
  local config_sha output branch preparation chi residual_tol max_iterations fluxes minimum_step overlap_alarm startup_source checkpoint_cadence mode multisite_update_alg execution_profile scratch_display added phase1_prior project_prior
  IFS=$'\t' read -r config_sha output branch preparation chi residual_tol max_iterations \
    fluxes minimum_step overlap_alarm startup_source checkpoint_cadence mode \
    multisite_update_alg execution_profile <<<"$validation"
  if [[ "$is_perlmutter" == true ]]; then
    scratch_display="$(resolve_scratch_root)/$SCRATCH_SUBDIRECTORY/job_<slurm-job-id>_${config_sha:0:12}"
  else
    scratch_display="\$PSCRATCH/$SCRATCH_SUBDIRECTORY/job_<slurm-job-id>_${config_sha:0:12}"
  fi
  verify_budget
  cat <<EOF
Project B YC8-1 chi=1024 bridge plan
  operator action: $action
  launcher version: $LAUNCHER_VERSION
  campaign mode: $mode
  execution profile: $execution_profile
  configuration: $config_path
  configuration SHA-256: $config_sha
  geometry: YC8-1; U(1); uniform twist gauge; MPS period 2
  branch: $branch
  preparation: $preparation
  chi / VUMPS outer-residual target: $chi / $residual_tol
  VUMPS multisite update: $multisite_update_alg
  outer-iteration cap per point: $max_iterations
  flux grid: $fluxes
  startup source: $startup_source
  adaptive bisection floor: $minimum_step pi
  overlap alarm floor: $overlap_alarm per site (alarm only; multimetric gates decide acceptance)
  fixed-theta growth before flux: enabled for the default bridge
  reverse validation before full-sweep promotion: required
  checkpoints: every $checkpoint_cadence target-chi outer iterations and after growth stages
  scratch package: $scratch_display
  scratch contents: full state payloads and optimizer checkpoints (excluded from routine sync)
  project contents: compact state manifests, resume TOMLs, logs, and accounting
  Slurm pre-timeout signal: USR1 at $PRETIMEOUT_SIGNAL_SECONDS seconds remaining
  resources: allocation-logical-cpus=$ALLOCATION_CPUS solver-step-logical-cpus=$SOLVER_STEP_CPUS julia-threads=$JULIA_THREADS memory=$MEMORY qos=$QOS time=$TIME_LIMIT
  worst-case charge: $FORECAST_NODE_HOURS node-hours
  compact output: $output
  immutable theta/pi=0.15 lineage parent changed: no
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
  [[ -d "$run_root" ]] || die "no YC8-1 bridge submissions are recorded"
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
  [[ -z "$requested_job_id" ]] || die "no bridge package records job $requested_job_id"
  [[ -n "$best_dir" ]] || die "no bridge job record is available"
  printf '%s\n' "$best_dir"
}

resolve_job_id() {
  local run_dir="$1"
  local job_id
  job_id="$(awk -F '\t' 'NR == 2 {print $1}' "$run_dir/job.tsv")"
  [[ "$job_id" =~ ^[0-9]+$ ]] || die "invalid job record"
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
      fluxes minimum_step overlap_alarm startup_source checkpoint_cadence mode \
      multisite_update_alg execution_profile <<<"$validation"
    run_worker_preflight "$config_path" "$config_sha"
    print_plan "$command_name" "$config_path" "$validation"
    if [[ "$command_name" == submit ]]; then
      pb_submission_lock "$project_root"
      verify_live_submission_state
      verify_budget
      verify_clean_target "$output"
      [[ -f "$worker" ]] || die "missing batch worker: $worker"
      mkdir -p "$run_root"
      run_id="$(date -u +%Y%m%dT%H%M%SZ)-yc8-1-chi1024-$mode"
      run_dir="$run_root/$run_id"
      [[ ! -e "$run_dir" ]] || die "run package already exists: $run_dir"
      mkdir -p "$run_dir/logs" "$run_dir/metrics"
      cp "$config_path" "$run_dir/config.snapshot.toml"
      printf '%s\n' "$config_sha" >"$run_dir/config.sha256"
      printf '%s\n' "$FORECAST_NODE_HOURS" >"$run_dir/forecast_node_hours.txt"
      raw_job_id="$(sbatch --parsable --job-name="$JOB_NAME" \
        --account="$phase1_account" --constraint=cpu --qos="$QOS" \
        --licenses=scratch --nodes=1 --ntasks=1 --cpus-per-task="$ALLOCATION_CPUS" \
        --mem="$MEMORY" --time="$TIME_LIMIT" --chdir="$project_root" \
        --signal="B:USR1@$PRETIMEOUT_SIGNAL_SECONDS" \
        --output="$run_dir/logs/scan-%j.out" --export=ALL \
        "$worker" "$project_root" "$config_path" "$config_sha" "$run_dir" "$julia_bin")"
      job_id="${raw_job_id%%;*}"
      [[ "$job_id" =~ ^[0-9]+$ ]] || die "Slurm returned an invalid job ID: $raw_job_id"
      printf 'job_id\tphase\tgeometry\tmode\texecution_profile\tmultisite_update_alg\tbranch\tchi\tconfig_sha256\tallocation_cpus\tsolver_step_cpus\tjulia_threads\tmemory\ttime_limit\tforecast_node_hours\tstartup_source\tcheckpoint_cadence\tpretimeout_signal_seconds\tstate_storage\tcheckpoint_storage\n' >"$run_dir/job.tsv"
      printf '%s\t1\tYC8-1\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tperlmutter_scratch\tperlmutter_scratch\n' \
        "$job_id" "$mode" "$execution_profile" "$multisite_update_alg" "$branch" "$chi" \
        "$config_sha" "$ALLOCATION_CPUS" "$SOLVER_STEP_CPUS" "$JULIA_THREADS" \
        "$MEMORY" "$TIME_LIMIT" "$FORECAST_NODE_HOURS" \
        "$startup_source" "$checkpoint_cadence" "$PRETIMEOUT_SIGNAL_SECONDS" \
        >>"$run_dir/job.tsv"
      printf '%s\n' "$run_dir" >"$run_root/latest_run.txt"
      printf 'Slurm accepted YC8-1 chi=1024 bridge job %s.\n' "$job_id"
      printf 'Run package: %s\n' "$run_dir"
      printf 'Next command: bash slurm/run_yc8_1_chi1024_bridge_cpu.sh status\n'
    fi
    ;;
  status)
    [[ $# -le 1 ]] || usage
    require_perlmutter status
    requested_job_id="${1:-}"
    [[ -z "$requested_job_id" || "$requested_job_id" =~ ^[0-9]+$ ]] || die "invalid job ID"
    run_dir="$(resolve_run_dir "$requested_job_id")"
    job_id="$(resolve_job_id "$run_dir")"
    squeue -j "$job_id" -o '%.18i %.12T %.10M %.10l %.6D %.6C %R' 2>/dev/null || true
    sacct -j "$job_id" --starttime=2026-08-01 \
      --format=JobIDRaw,JobName,State,Elapsed,Timelimit,NNodes,NCPUS,ExitCode,MaxRSS,AveRSS,ReqMem
    ;;
  reconcile)
    [[ $# -le 1 ]] || usage
    require_perlmutter reconcile
    requested_job_id="${1:-}"
    [[ -z "$requested_job_id" || "$requested_job_id" =~ ^[0-9]+$ ]] || die "invalid job ID"
    run_dir="$(resolve_run_dir "$requested_job_id")"
    job_id="$(resolve_job_id "$run_dir")"
    pb_reconcile "$project_root"
    ;;
  *)
    usage
    ;;
esac
