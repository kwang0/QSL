#!/usr/bin/env bash
set -euo pipefail

# Guarded, one-job Shared-QOS resource benchmark. The literal `submit` action
# authorizes only this benchmark; it cannot submit a scientific continuation.

readonly DEFAULT_ACCOUNT="m4863"
readonly ACTIVE_CONTROL_REF="configs/phase1_idmrg_benchmark_active_control.ref"

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/slurm/lib/project_b_resources.sh"
julia_bin="${JULIA_BIN:-julia}"
phase1_account="${PHASE1_ACCOUNT:-$DEFAULT_ACCOUNT}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage:
  bash slurm/run_idmrg_benchmark_cpu.sh plan [CONTROL.toml]
  bash slurm/run_idmrg_benchmark_cpu.sh submit [CONTROL.toml]
  bash slurm/run_idmrg_benchmark_cpu.sh status [CONTROL.toml] [JOB_ID]
  bash slurm/run_idmrg_benchmark_cpu.sh reconcile [CONTROL.toml] [JOB_ID]
  bash slurm/run_idmrg_benchmark_cpu.sh analyze [CONTROL.toml]

With no CONTROL argument, the launcher uses the hash-pinned benchmark control
named by configs/phase1_idmrg_benchmark_active_control.ref. The literal submit
command authorizes one low-cost benchmark job only. It never submits or
promotes a scientific continuation.
EOF
  exit 2
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
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
    [[ -f "$ref_path" ]] || die "missing active benchmark reference: $ref_path"
    requested="$(sed -n '1p' "$ref_path")"
    expected_sha="$(sed -n '2p' "$ref_path")"
    [[ "$requested" == output/phase1_idmrg/benchmarks/* ]] ||
      die "active benchmark reference has an unsafe path: $requested"
    [[ "$requested" != *..* ]] ||
      die "active benchmark reference may not contain '..'"
    [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] ||
      die "active benchmark reference has an invalid SHA-256"
    requested="$project_root/$requested"
  fi
  [[ -f "$requested" ]] || die "missing benchmark control: $requested"
  local resolved
  resolved="$(cd "$(dirname "$requested")" && pwd)/$(basename "$requested")"
  if [[ -n "$expected_sha" ]]; then
    [[ "$(sha256_file "$resolved")" == "$expected_sha" ]] ||
      die "active benchmark control SHA-256 does not match $ref_path"
  fi
  printf '%s\n' "$resolved"
}

parse_arguments() {
  control_argument=""
  job_id_argument=""
  case "$command_name" in
    plan|submit|analyze)
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
parse_arguments "$@"
control_path="$(resolve_control "$control_argument")"
command -v "$julia_bin" >/dev/null 2>&1 || die "Julia is unavailable: $julia_bin"
[[ "$phase1_account" =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid PHASE1_ACCOUNT"
case "$command_name" in
  submit|status|reconcile)
    require_perlmutter "$command_name"
    ;;
  analyze)
    [[ "$is_perlmutter" != true ]] ||
      die "analyze is a local post-Globus command"
    ;;
esac

validator_arguments=("$control_path")
if [[ "$command_name" == analyze ]]; then
  validator_arguments+=(--postprocess)
fi
validation="$($julia_bin --startup-file=no --project="$project_root/idmrg" \
  "$project_root/idmrg/scripts/validate_benchmark_control.jl" \
  "${validator_arguments[@]}")"
IFS=$'\t' read -r control_sha science_control result_seed thread_csv \
  cpus_per_julia_thread warmup_iterations measured_iterations total_iterations \
  result_directory analysis_path nodes cpus memory time_limit qos \
  maximum_new_node_hours prior_phase1 phase1_ceiling prior_project project_ceiling \
  <<<"$validation"
[[ "$control_sha" =~ ^[0-9a-f]{64}$ ]] || die "validator returned an invalid hash"
package_directory="$(dirname "$control_path")"
job_id_file="$package_directory/job_id.txt"

verify_submission_targets() {
  [[ ! -e "$job_id_file" ]] || die "benchmark already recorded a job: $job_id_file"
  IFS=',' read -r -a thread_values <<<"$thread_csv"
  for threads in "${thread_values[@]}"; do
    [[ ! -e "$result_directory/benchmark_threads_${threads}.h5" ]] ||
      die "refusing to overwrite benchmark result for $threads threads"
    [[ ! -e "$result_directory/benchmark_threads_${threads}.h5.tmp" ]] ||
      die "refusing to ignore stale benchmark temporary result for $threads threads"
  done
  [[ ! -e "$analysis_path" ]] || die "refusing to overwrite benchmark analysis"
}

print_failure_diagnosis() {
  local job_id="$1"
  local log_path="$package_directory/logs/benchmark-${job_id}.out"
  if [[ ! -f "$log_path" ]]; then
    printf 'Benchmark failure log is not synced: %s\n' "$log_path" >&2
    return
  fi
  if grep -Fq 'no method matching strides(::BitVector)' "$log_path"; then
    printf '%s\n' \
      'Benchmark failure diagnosis: HDF5 result serialization rejected a packed BitVector after the first 2-thread updates.' >&2
  elif grep -Fq 'UndefVarError: `cputime` not defined in `Base`' "$log_path"; then
    printf '%s\n' \
      'Benchmark failure diagnosis: Julia 1.12 timing-API compatibility failure before the first iDMRG update.' >&2
  elif grep -Fq '/var/spool/slurmd/idmrg/scripts/validate_benchmark_control.jl' \
      "$log_path"; then
    printf '%s\n' \
      'Benchmark failure diagnosis: Slurm-spooled worker resolved the wrong project root before loading the solver.' >&2
  else
    printf 'Benchmark failure diagnosis is not recognized automatically; inspect %s\n' \
      "$log_path" >&2
  fi
}

print_plan() {
  local action="$1"
  cat <<EOF
Project B Phase 1 iDMRG resource benchmark plan
  operator action: $action
  benchmark control: $control_path
  control SHA-256: $control_sha
  immutable numerical seed: $result_seed
  seed status: rejected/nonconverged; benchmark only; not the lineage parent
  target workload: theta/pi=0.2, YC8-1, period 2, U(1), chi 512
  independent Julia thread settings: $thread_csv
  iterations per setting: $total_iterations ($warmup_iterations warm-up + $measured_iterations measured)
  Slurm mapping: two logical CPUs per Julia thread; --cpu-bind=cores
  allocation: qos=$qos nodes=$nodes cpus-per-task=$cpus memory=$memory time=$time_limit
  maximum benchmark charge: $maximum_new_node_hours node-hours; one job
  Phase 1 budget: prior=$prior_phase1 ceiling=$phase1_ceiling node-hours
  project budget: prior=$prior_project ceiling=$project_ceiling node-hours
  checkpoints: disabled; no scratch or home checkpoint payload
  full state output: disabled; timing records only
  science submission/promotion: disabled
  submission authorization: literal submit command
EOF
  verify_submission_targets
  local tmp_worker
  tmp_worker="$(mktemp -d)"
  cp "$project_root/slurm/run_idmrg_benchmark_job.sh" "$tmp_worker/worker.sh"
  worker_preflight="$(PROJECT_B_JULIA_BIN="$julia_bin" \
    bash "$tmp_worker/worker.sh" \
    preflight "$project_root" "$control_path")"
  rm -r "$tmp_worker"
  grep -q 'Benchmark worker preflight passed' <<<"$worker_preflight" ||
    die "benchmark worker preflight did not confirm success"
  printf '  worker preflight: passed with explicit root, Julia timing, and HDF5 result I/O\n'
  if [[ "$is_perlmutter" == true ]]; then
    command -v squeue >/dev/null || die "squeue is unavailable"
    pb_guard "$project_root" "$maximum_new_node_hours" live
    printf '  accounting authority: live Perlmutter checks passed\n'
  else
    printf '  accounting authority: LOCAL STRUCTURAL PLAN ONLY; Perlmutter state not verified\n'
  fi
}

resolve_job_id() {
  local requested="${1:-}"
  if [[ -z "$requested" ]]; then
    [[ -f "$job_id_file" ]] ||
      die "missing recorded benchmark job ID; run submit or pass JOB_ID"
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
    pb_submission_lock "$project_root"
    print_plan submit
    mkdir -p "$package_directory/logs"
    raw_job_id="$(sbatch --parsable --job-name=pb1-idmrg-bench \
      --account="$phase1_account" --constraint=cpu --qos="$qos" \
      --nodes="$nodes" --ntasks=1 --cpus-per-task="$cpus" --mem="$memory" \
      --time="$time_limit" --chdir="$project_root" \
      --output="$package_directory/logs/benchmark-%j.out" \
      --export="ALL,PROJECT_B_JULIA_BIN=$julia_bin" \
      "$project_root/slurm/run_idmrg_benchmark_job.sh" \
      run "$project_root" "$control_path")"
    job_id="${raw_job_id%%;*}"
    [[ "$job_id" =~ ^[0-9]+$ ]] || die "Slurm returned an invalid job ID: $raw_job_id"
    temporary_job_id_file="$job_id_file.tmp.$$"
    printf '%s\n' "$job_id" >"$temporary_job_id_file"
    mv "$temporary_job_id_file" "$job_id_file"
    printf 'Slurm accepted benchmark job %s.\n' "$job_id"
    printf 'Next command: bash slurm/run_idmrg_benchmark_cpu.sh status\n'
    ;;
  status)
    job_id="$(resolve_job_id "$job_id_argument")"
    if ! squeue -j "$job_id" -o '%.18i %.12T %.10M %.10l %.6D %.6C %R' \
        2>/dev/null; then
      printf 'Job %s is no longer in the live queue; showing accounting below.\n' \
        "$job_id"
    fi
    sacct -j "$job_id" --starttime=2026-08-01 \
      --format=JobIDRaw,JobName,State,Elapsed,Timelimit,NNodes,NCPUS,ExitCode
    ;;
  reconcile)
    job_id="$(resolve_job_id "$job_id_argument")"
    summary="$package_directory/sacct-${job_id}.tsv"
    steps="$package_directory/sacct-steps-${job_id}.tsv"
    if [[ -e "$summary" && -e "$steps" ]]; then pb_reconcile "$project_root"; exit 0; fi
    [[ ! -e "$summary" && ! -e "$steps" ]] || die "partial accounting exists; use common reconcile"
    summary_temporary="$summary.tmp"
    steps_temporary="$steps.tmp"
    sacct -j "$job_id" --starttime=2026-08-01 -n -P -X \
      --format=JobIDRaw,JobName,State,ElapsedRaw,TimelimitRaw,NNodes,NCPUS,ExitCode \
      >"$summary_temporary"
    [[ -s "$summary_temporary" ]] || die "accounting has not populated for $job_id"
    job_state="$(awk -F '|' -v job_id="$job_id" '$1 == job_id { print $3; exit }' \
      "$summary_temporary")"
    [[ -n "$job_state" ]] || die "accounting has no exact job record for $job_id"
    normalized_state="${job_state%% *}"
    normalized_state="${normalized_state%%+*}"
    case "$normalized_state" in
      COMPLETED|FAILED|CANCELLED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|PREEMPTED|BOOT_FAIL|DEADLINE|REVOKED|SPECIAL_EXIT)
        ;;
      *)
        rm -f "$summary_temporary"
        die "job $job_id is not terminal (state $job_state); run status and wait"
        ;;
    esac
    sacct -j "$job_id" --starttime=2026-08-01 -P \
      --format=JobIDRaw,JobName,State,ElapsedRaw,Elapsed,TimelimitRaw,NNodes,NCPUS,AllocCPUS,TotalCPU,AveCPU,MaxRSS,AveRSS,ExitCode \
      >"$steps_temporary"
    [[ -s "$steps_temporary" ]] || die "step accounting has not populated for $job_id"
    mv "$summary_temporary" "$summary"
    mv "$steps_temporary" "$steps"
    pb_reconcile "$project_root"
    printf 'Reconciled terminal benchmark job %s (%s).\n' "$job_id" "$job_state"
    printf 'Step efficiency evidence: %s\n' "$steps"
    if [[ "$normalized_state" != COMPLETED ]]; then
      print_failure_diagnosis "$job_id"
      printf 'Benchmark produced no valid timing result; inspect %s/logs before preparing a retry.\n' \
        "$package_directory"
    fi
    ;;
  analyze)
    [[ -f "$job_id_file" ]] || die "missing synced benchmark job ID"
    job_id="$(resolve_job_id)"
    summary="$package_directory/sacct-${job_id}.tsv"
    [[ -f "$summary" ]] || die "missing synced benchmark accounting: $summary"
    job_state="$(awk -F '|' -v job_id="$job_id" '$1 == job_id { print $3; exit }' \
      "$summary")"
    normalized_state="${job_state%% *}"
    normalized_state="${normalized_state%%+*}"
    if [[ "$normalized_state" != COMPLETED ]]; then
      print_failure_diagnosis "$job_id"
      die "benchmark job $job_id ended $job_state; no timing analysis is valid"
    fi
    steps="$package_directory/sacct-steps-${job_id}.tsv"
    [[ -f "$steps" ]] || die "missing synced step accounting: $steps"
    IFS=',' read -r -a thread_values <<<"$thread_csv"
    for threads in "${thread_values[@]}"; do
      [[ -f "$result_directory/benchmark_threads_${threads}.h5" ]] ||
        die "missing synced result for $threads threads"
    done
    "$julia_bin" --startup-file=no --project="$project_root/idmrg" \
      "$project_root/scripts/analyze_phase1_idmrg_benchmark.jl" \
      "$control_path" "$job_id" "$steps" "$analysis_path"
    ;;
esac
