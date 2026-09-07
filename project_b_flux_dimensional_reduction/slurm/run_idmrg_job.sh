#!/usr/bin/env bash
set -euo pipefail
[[ $# == 7 ]] || { echo 'usage: MODE PROJECT_ROOT CONTROL RESULT STEP_CPUS THREADS JULIA' >&2; exit 2; }
mode="$1" project_root="$2" control="$3" result="$4" step_cpus="$5" threads="$6" julia_bin="$7"
[[ "$mode" == preflight || "$mode" == run ]] || exit 2
[[ "$project_root" == /* && -f "$project_root/idmrg/Project.toml" ]] || exit 2
"$julia_bin" --startup-file=no --project="$project_root/idmrg" "$project_root/idmrg/scripts/validate_control.jl" "$control" >/dev/null
[[ "$mode" != preflight ]] || { echo 'iDMRG copied worker preflight passed'; exit 0; }
[[ -n "${SLURM_JOB_ID:-}" && -x /usr/bin/time ]] || exit 2
mkdir -p "$(dirname "$result")"
exec srun --exact --exclusive --nodes=1 --ntasks=1 --cpus-per-task="$step_cpus" --cpu-bind=cores \
  /usr/bin/time -v -o "$(dirname "$result")/julia-resource.time" \
  env JULIA_NUM_THREADS="$threads" OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 OMP_NUM_THREADS=1 \
  "$julia_bin" --startup-file=no --project="$project_root/idmrg" \
  "$project_root/idmrg/scripts/run_idmrg.jl" "$control" "$result"
