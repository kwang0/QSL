#!/usr/bin/env bash
set -euo pipefail
[[ $# == 6 ]] || { echo 'usage: MODE PROJECT_ROOT CONTROL SHA RUN_DIR JULIA' >&2; exit 2; }
mode="$1" project_root="$2" control="$3" expected_sha="$4" run_dir="$5" julia_bin="$6"
[[ "$mode" == preflight || "$mode" == run ]] || exit 2
[[ "$project_root" == /* && -f "$project_root/Project.toml" ]] || exit 2
[[ "$(sha256sum "$control" | awk '{print $1}')" == "$expected_sha" ]] || exit 2
record="$("$julia_bin" --startup-file=no "$project_root/scripts/validate_mpskit_solver_pilot.jl" "$control")"
IFS=$'\t' read -r hash forecast cpus step threads memory time_limit pretimeout <<<"$record"
if [[ "$mode" == preflight ]]; then
  export JULIA_NUM_THREADS="$threads" OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 OMP_NUM_THREADS=1
  "$julia_bin" --startup-file=no --project="$project_root/idmrg" "$project_root/idmrg/scripts/preflight_solver_pilot.jl"
  echo 'Copied pilot worker preflight passed'
  exit 0
fi
[[ "${SLURM_CPUS_PER_TASK:-0}" == "$cpus" && -n "${SLURM_JOB_ID:-}" ]] || exit 2
[[ "${PSCRATCH:-}" == /pscratch/* && -d "$PSCRATCH" && -x /usr/bin/time ]] || exit 2
"$julia_bin" --startup-file=no "$project_root/scripts/validate_mpskit_solver_pilot.jl" "$control" --live >/dev/null
scratch="$PSCRATCH/QSL/project_b_flux_dimensional_reduction/solver_pilot/job_${SLURM_JOB_ID}_${hash:0:12}"
[[ ! -e "$scratch" ]] || { echo 'Scratch pilot package exists' >&2; exit 2; }
mkdir -p "$scratch" "$run_dir/metrics"
export JULIA_NUM_THREADS="$threads" OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 OMP_NUM_THREADS=1
export PROJECT_B_PRETIMEOUT_REQUEST_FILE="$run_dir/pretimeout.request"
export PROJECT_B_PILOT_DEADLINE="$(($(date +%s)+39600))"
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
for stage in baseline_vumps difficult_vumps difficult_gradient; do
  [[ ! -e "$PROJECT_B_PRETIMEOUT_REQUEST_FILE" && "$(date +%s)" -lt "$PROJECT_B_PILOT_DEADLINE" ]] || break
  run_step "$stage" "$julia_bin" --startup-file=no --project="$project_root/idmrg" \
    "$project_root/idmrg/scripts/run_solver_pilot.jl" "$control" "$stage" "$scratch" "$run_dir"
  [[ ! -e "$PROJECT_B_PRETIMEOUT_REQUEST_FILE" && "$(date +%s)" -lt "$PROJECT_B_PILOT_DEADLINE" ]] || break
  run_step "analysis_$stage" "$julia_bin" --startup-file=no --project="$project_root" \
    "$project_root/scripts/analyze_mpskit_solver_pilot.jl" "$control" "$run_dir/$stage.toml"
done
printf 'finished_utc=%s\npretimeout_requested=%s\n' "$(date -u +%FT%TZ)" \
  "$([[ -e "$PROJECT_B_PRETIMEOUT_REQUEST_FILE" ]] && echo true || echo false)" >"$run_dir/job.result"
