#!/usr/bin/env bash
set -euo pipefail
[[ $# == 6 ]] || { echo 'usage: MODE PROJECT_ROOT CONTROL SHA RUN_DIR JULIA' >&2; exit 2; }
mode="$1" project_root="$2" control="$3" expected_sha="$4" run_dir="$5" julia_bin="$6"
[[ "$mode" == preflight || "$mode" == run ]] || exit 2
[[ "$project_root" == /* && -f "$project_root/Project.toml" ]] || exit 2
[[ "$(sha256sum "$control" | awk '{print $1}')" == "$expected_sha" ]] || exit 2
record="$("$julia_bin" --startup-file=no "$project_root/scripts/validate_relaxation_continuation.jl" "$control")"
IFS=$'\t' read -r hash forecast cpus step threads memory time_limit pretimeout <<<"$record"
export JULIA_NUM_THREADS="$threads" OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 OMP_NUM_THREADS=1
if [[ "$mode" == preflight ]]; then
  "$julia_bin" --startup-file=no --project="$project_root/idmrg" "$project_root/idmrg/test/relaxation_continuation.jl"
  "$julia_bin" --startup-file=no --project="$project_root" "$project_root/test/relaxation_analysis.jl"
  echo 'Copied relaxation worker preflight passed'
  exit 0
fi
[[ "${SLURM_CPUS_PER_TASK:-0}" == "$cpus" && -n "${SLURM_JOB_ID:-}" ]] || exit 2
[[ "${PSCRATCH:-}" == /pscratch/* && -d "$PSCRATCH" && -x /usr/bin/time ]] || exit 2
scratch="$PSCRATCH/QSL/project_b_flux_dimensional_reduction/relaxation/job_${SLURM_JOB_ID}_${hash:0:12}"
[[ ! -e "$scratch" ]] || { echo 'Scratch package exists' >&2; exit 2; }
mkdir -p "$scratch" "$run_dir/metrics"
export PROJECT_B_PRETIMEOUT_REQUEST_FILE="$run_dir/pretimeout.request"
export PROJECT_B_RELAXATION_DEADLINE="$(($(date +%s)+122400))"
trap 'printf "USR1\n" >"$PROJECT_B_PRETIMEOUT_REQUEST_FILE"' USR1
printf 'scratch_package\t%s\ncontrol_sha256\t%s\nallocation_cpus\t%s\n' "$scratch" "$hash" "$cpus" >"$run_dir/worker.tsv"
run_step() {
  local label="$1"; shift
  srun --exact --exclusive --nodes=1 --ntasks=1 --cpus-per-task="$step" --cpu-bind=cores \
    /usr/bin/time -v -o "$run_dir/metrics/$label.time" "$@" &
  local pid=$! status
  while true; do
    if wait "$pid"; then status=0; else status=$?; fi
    kill -0 "$pid" 2>/dev/null || return "$status"
  done
}
for arm in baseline n8_grid1 n8_grid2 n16_grid1 n16_grid2 n32_grid1 n32_grid2; do
  [[ ! -e "$PROJECT_B_PRETIMEOUT_REQUEST_FILE" && "$(date +%s)" -lt "$PROJECT_B_RELAXATION_DEADLINE" ]] || break
  run_step "$arm" "$julia_bin" --startup-file=no --project="$project_root/idmrg" \
    "$project_root/idmrg/scripts/run_relaxation_continuation.jl" "$control" "$arm" "$scratch" "$run_dir"
  [[ ! -e "$PROJECT_B_PRETIMEOUT_REQUEST_FILE" ]] || break
  run_step "analysis_$arm" "$julia_bin" --startup-file=no --project="$project_root" \
    "$project_root/scripts/analyze_relaxation_continuation.jl" "$control" "$run_dir" "$arm"
done
"$julia_bin" --startup-file=no "$project_root/scripts/summarize_relaxation_continuation.jl" "$run_dir" >"$run_dir/summary.txt"
cat "$run_dir/summary.txt"
printf 'finished_utc=%s\npretimeout_requested=%s\n' "$(date -u +%FT%TZ)" \
  "$([[ -e "$PROJECT_B_PRETIMEOUT_REQUEST_FILE" ]] && echo true || echo false)" >"$run_dir/job.result"
