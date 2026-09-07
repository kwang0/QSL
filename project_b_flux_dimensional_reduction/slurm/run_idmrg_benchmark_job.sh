#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 3 ]] || {
  printf 'usage: run_idmrg_benchmark_job.sh preflight|run PROJECT_ROOT BENCHMARK_CONTROL.toml\n' >&2
  exit 2
}

mode="$1"
[[ "$mode" == preflight || "$mode" == run ]] || {
  printf 'ERROR: worker mode must be preflight or run\n' >&2
  exit 2
}
[[ "$2" == /* ]] || {
  printf 'ERROR: PROJECT_ROOT must be absolute: %s\n' "$2" >&2
  exit 1
}
project_root="$(cd "$2" && pwd)"
control_path="$3"
[[ -f "$project_root/idmrg/Project.toml" ]] || {
  printf 'ERROR: invalid explicit project root: %s\n' "$project_root" >&2
  exit 1
}
[[ -f "$project_root/idmrg/scripts/validate_benchmark_control.jl" ]] || {
  printf 'ERROR: missing benchmark validator below explicit project root\n' >&2
  exit 1
}
[[ -f "$control_path" ]] || {
  printf 'ERROR: missing benchmark control: %s\n' "$control_path" >&2
  exit 1
}
julia_bin="${PROJECT_B_JULIA_BIN:-julia}"
validation="$($julia_bin --startup-file=no --project="$project_root/idmrg" \
  "$project_root/idmrg/scripts/validate_benchmark_control.jl" "$control_path")"
IFS=$'\t' read -r control_sha science_control result_seed thread_csv \
  cpus_per_julia_thread warmup_iterations measured_iterations total_iterations \
  result_directory analysis_path nodes allocation_cpus memory time_limit qos \
  maximum_new_node_hours prior_phase1 phase1_ceiling prior_project project_ceiling \
  <<<"$validation"

runtime_preflight="$($julia_bin --startup-file=no --project="$project_root/idmrg" \
  "$project_root/idmrg/scripts/preflight_benchmark_runtime.jl")"
grep -q 'Benchmark executable timing preflight passed' <<<"$runtime_preflight" || {
  printf 'ERROR: benchmark executable timing preflight did not confirm success\n' >&2
  exit 1
}
grep -q 'Benchmark executable HDF5-result preflight passed' <<<"$runtime_preflight" || {
  printf 'ERROR: benchmark executable HDF5-result preflight did not confirm success\n' >&2
  exit 1
}

if [[ "$mode" == preflight ]]; then
  printf 'Benchmark worker preflight passed: explicit project root=%s\n' "$project_root"
  printf 'Benchmark worker preflight passed: control SHA-256=%s\n' "$control_sha"
  printf 'Benchmark worker preflight passed: Julia-1.12 timing and HDF5-result paths executed\n'
  exit 0
fi

printf '%s\n' "$runtime_preflight"

mkdir -p "$result_directory"
IFS=',' read -r -a thread_values <<<"$thread_csv"
for threads in "${thread_values[@]}"; do
  step_cpus=$((threads * cpus_per_julia_thread))
  result_path="$result_directory/benchmark_threads_${threads}.h5"
  [[ ! -e "$result_path" ]] || {
    printf 'ERROR: refusing to overwrite benchmark result: %s\n' "$result_path" >&2
    exit 1
  }
  printf 'Starting independent benchmark: Julia threads=%s, Slurm logical CPUs=%s\n' \
    "$threads" "$step_cpus"
  srun --exact --exclusive --nodes=1 --ntasks=1 \
    --cpus-per-task="$step_cpus" --cpu-bind=cores \
    --job-name="pb1-idmrg-t${threads}" --kill-on-bad-exit=1 \
    /usr/bin/time -v -o "$result_directory/resource_threads_${threads}.time" \
    env JULIA_NUM_THREADS="$threads" OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 OMP_NUM_THREADS=1 \
    "$julia_bin" --startup-file=no --project="$project_root/idmrg" \
    "$project_root/idmrg/scripts/run_benchmark.jl" \
    "$control_path" "$threads" "$result_path"
done

printf 'All controlled iDMRG thread benchmarks completed.\n'
