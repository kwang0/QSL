#!/usr/bin/env bash
set -euo pipefail
[[ $# == 6 ]] || { echo 'usage: MODE ROOT CONTROL SHA RUN_DIR JULIA' >&2; exit 2; }
mode="$1" project_root="$2" control="$3" expected_sha="$4" run_dir="$5" julia_bin="$6"
[[ "$mode" == preflight || "$mode" == run ]] || exit 2
die() { printf 'ERROR [%s]: %s\n' "${stage:-arguments}" "$*" >&2; exit 2; }
[[ "$project_root" == /* && -f "$project_root/Project.toml" ]] || die 'invalid project root'
stage=control_validation
if [[ "$mode" == run ]]; then
  [[ -d "$run_dir" ]] || die 'missing launch package'
  trap 'status=$?; if ((status!=0)) && [[ ! -e "$run_dir/job.result" ]]; then
    printf "benchmark_complete=false\nstep_failure=1\nexit_code=%s\nstage=%s\n" "$status" "$stage" >"$run_dir/job.result"
    printf "ERROR: worker exited at %s (exit %s)\n" "$stage" "$status" >&2
  fi' EXIT
  printf 'job_id\t%s\ncpus_per_task\t%s\njob_cpus_per_node\t%s\njob_num_nodes\t%s\npscratch\t%s\n' \
    "${SLURM_JOB_ID:-}" "${SLURM_CPUS_PER_TASK:-}" "${SLURM_JOB_CPUS_PER_NODE:-}" \
    "${SLURM_JOB_NUM_NODES:-${SLURM_NNODES:-}}" "${PSCRATCH:-}" >"$run_dir/startup.tsv"
  cat "$run_dir/startup.tsv"
fi
[[ "$(sha256sum "$control" | awk '{print $1}')" == "$expected_sha" ]] || die 'control hash mismatch'
record="$("$julia_bin" --startup-file=no "$project_root/scripts/validate_thread_benchmark.jl" "$control")"
IFS=$'\t' read -r hash forecast cpus step memory time_limit pretimeout <<<"$record"
"$julia_bin" --startup-file=no "$project_root/scripts/thread_benchmark/preflight.jl" "$project_root"
[[ "$mode" != preflight ]] || exit 0
stage=allocation_validation
source "$project_root/slurm/thread_benchmark/resources.sh"
allocated_cpus="$(thread_benchmark_allocation "$cpus" "$step")"
printf 'Allocation accepted: %s CPUs; sealed ceiling %s; solver step %s.\n' "$allocated_cpus" "$cpus" "$step"
stage=scratch_validation
[[ "${PSCRATCH:-}" == /pscratch/* && -d "$PSCRATCH" ]] || die "PSCRATCH directory unavailable: ${PSCRATCH:-unset}"
[[ -x /usr/bin/time ]] || die '/usr/bin/time is unavailable on this node'
scratch="$PSCRATCH/QSL/project_b_flux_dimensional_reduction/thread_benchmark/job_${SLURM_JOB_ID}_${hash:0:12}"
[[ ! -e "$scratch" ]] || die 'scratch package exists'
mkdir -p "$scratch" "$run_dir/metrics"
export PROJECT_B_PRETIMEOUT_REQUEST_FILE="$run_dir/pretimeout.request"
export PROJECT_B_THREAD_BENCHMARK_DEADLINE="$(($(date +%s)+21600))"
trap 'printf "USR1\n" >"$PROJECT_B_PRETIMEOUT_REQUEST_FILE"' USR1
printf 'scratch_package\t%s\ncontrol_sha256\t%s\nallocation_cpus\t%s\nrequested_cpus\t%s\n' \
  "$scratch" "$hash" "$allocated_cpus" "$cpus" >"$run_dir/worker.tsv"
printf 'step\texit_code\n' >"$run_dir/step_exit_codes.tsv"
run_step() {
  local label="$1" threads="$2" blas="$3"; shift 3
  stage="$label"
  srun --exact --exclusive --nodes=1 --ntasks=1 --cpus-per-task="$step" --cpu-bind=cores \
    env LC_ALL=C JULIA_NUM_THREADS="$threads" OPENBLAS_NUM_THREADS="$blas" MKL_NUM_THREADS="$blas" OMP_NUM_THREADS=1 \
    /usr/bin/time -v -o "$run_dir/metrics/$label.time" "$@" &
  local pid=$! status
  while true; do
    if wait "$pid"; then status=0; else status=$?; fi
    kill -0 "$pid" 2>/dev/null || break
  done
  printf '%s\t%s\n' "$label" "$status" >>"$run_dir/step_exit_codes.tsv"
  return "$status"
}
failed=0
if ! run_step export 2 1 "$julia_bin" --startup-file=no --project="$project_root" \
    "$project_root/scripts/thread_benchmark/export_seed.jl" "$control" "$scratch" "$run_dir"; then failed=1
elif ! run_step prepare 2 1 "$julia_bin" --startup-file=no --project="$project_root/idmrg" \
    "$project_root/idmrg/thread_benchmark/run.jl" prepare "$control" "$run_dir"; then failed=1
else
  for setting in j2_b1 j2_b4 j1_b8; do
    [[ ! -e "$PROJECT_B_PRETIMEOUT_REQUEST_FILE" && "$(date +%s)" -lt "$PROJECT_B_THREAD_BENCHMARK_DEADLINE" ]] || { failed=1; break; }
    case "$setting" in j2_b1) threads=2; blas=1;; j2_b4) threads=2; blas=4;; j1_b8) threads=1; blas=8;; esac
    run_step "$setting" "$threads" "$blas" "$julia_bin" --startup-file=no --project="$project_root/idmrg" \
      "$project_root/idmrg/thread_benchmark/run.jl" run "$control" "$setting" "$run_dir" || failed=1
  done
fi
complete=false
stage=summary
if [[ "$failed" == 0 ]] && "$julia_bin" --startup-file=no "$project_root/scripts/summarize_thread_benchmark.jl" "$run_dir" >"$run_dir/summary.txt"; then complete=true
else failed=1; fi
printf 'benchmark_complete=%s\nstep_failure=%s\n' "$complete" "$failed" >"$run_dir/job.result"
[[ ! -f "$run_dir/summary.txt" ]] || cat "$run_dir/summary.txt"
exit "$failed"
