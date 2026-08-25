#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
julia_bin="${JULIA_BIN:-}"
if [[ -z "$julia_bin" ]]; then
  julia_bin="$(command -v julia || true)"
fi
if [[ -z "$julia_bin" ]]; then
  printf 'SKIP: Julia is unavailable\n'
  exit 0
fi

output="$(JULIA_BIN="$julia_bin" \
  bash "$project_root/slurm/run_idmrg_benchmark_cpu.sh" plan)"
grep -q 'LOCAL STRUCTURAL PLAN ONLY' <<<"$output"
grep -q 'independent Julia thread settings: 2,4,8,16' <<<"$output"
grep -q 'qos=shared nodes=1 cpus-per-task=32 memory=16G' <<<"$output"
grep -q 'maximum benchmark charge: 0.1875 node-hours' <<<"$output"
grep -q 'checkpoints: disabled' <<<"$output"
grep -q 'science submission/promotion: disabled' <<<"$output"
grep -q 'submission authorization: literal submit command' <<<"$output"
grep -q 'worker preflight: passed with explicit root, Julia timing, and HDF5 result I/O' \
  <<<"$output"

grep -q -- '--cpu-bind=cores' "$project_root/slurm/run_idmrg_benchmark_job.sh"
grep -q 'JULIA_NUM_THREADS="$threads"' \
  "$project_root/slurm/run_idmrg_benchmark_job.sh"
if grep -q 'dirname "${BASH_SOURCE\[0\]}"' \
    "$project_root/slurm/run_idmrg_benchmark_job.sh"; then
  printf 'benchmark worker still derives project root from its Slurm-spooled path\n' >&2
  exit 1
fi
if grep -q 'write_checkpoint' "$project_root/idmrg/scripts/run_benchmark.jl"; then
  printf 'benchmark runner unexpectedly writes checkpoints\n' >&2
  exit 1
fi

temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
cp "$project_root/slurm/run_idmrg_benchmark_job.sh" "$temporary/slurm_script"
spooled_output="$(PROJECT_B_JULIA_BIN="$julia_bin" \
  bash "$temporary/slurm_script" preflight "$project_root" \
  "$project_root/$(sed -n '1p' \
    "$project_root/configs/phase1_idmrg_benchmark_active_control.ref")")"
grep -q 'Benchmark worker preflight passed: explicit project root=' \
  <<<"$spooled_output"
grep -q 'Benchmark worker preflight passed: Julia-1.12 timing and HDF5-result paths executed' \
  <<<"$spooled_output"
if rg -q 'Base\.cputime\(' "$project_root/idmrg/src/ProjectBIDMRG.jl"; then
  printf 'benchmark still calls the Julia-1.12-incompatible Base.cputime API\n' >&2
  exit 1
fi
failed_control="$project_root/output/phase1_idmrg/benchmarks/\
theta_p0p20000000_chi512_threads_from_c7ef67c0e22b/\
phase1_idmrg_benchmark_control.toml"
if JULIA_BIN="$julia_bin" bash "$project_root/slurm/run_idmrg_benchmark_cpu.sh" \
    analyze "$failed_control" >"$temporary/failed-analyze.out" 2>&1; then
  printf 'failed benchmark attempt unexpectedly produced a valid analysis\n' >&2
  exit 1
fi
grep -q 'ended FAILED; no timing analysis is valid' \
  "$temporary/failed-analyze.out"
grep -q 'Slurm-spooled worker resolved the wrong project root' \
  "$temporary/failed-analyze.out"
runtime_failed_control="$project_root/output/phase1_idmrg/benchmarks/\
theta_p0p20000000_chi512_threads_retry_after_57548405_c7ef67c0e22b/\
phase1_idmrg_benchmark_control.toml"
if JULIA_BIN="$julia_bin" bash "$project_root/slurm/run_idmrg_benchmark_cpu.sh" \
    analyze "$runtime_failed_control" \
    >"$temporary/runtime-failed-analyze.out" 2>&1; then
  printf 'runtime-failed benchmark attempt unexpectedly produced a valid analysis\n' >&2
  exit 1
fi
grep -q 'Julia 1.12 timing-API compatibility failure' \
  "$temporary/runtime-failed-analyze.out"
writer_failed_control="$project_root/output/phase1_idmrg/benchmarks/\
theta_p0p20000000_chi512_threads_retry_after_57550459_c7ef67c0e22b/\
phase1_idmrg_benchmark_control.toml"
if JULIA_BIN="$julia_bin" bash "$project_root/slurm/run_idmrg_benchmark_cpu.sh" \
    analyze "$writer_failed_control" \
    >"$temporary/writer-failed-analyze.out" 2>&1; then
  printf 'writer-failed benchmark attempt unexpectedly produced a valid analysis\n' >&2
  exit 1
fi
grep -q 'HDF5 result serialization rejected a packed BitVector' \
  "$temporary/writer-failed-analyze.out"
if JULIA_BIN="$julia_bin" \
    bash "$project_root/slurm/run_idmrg_benchmark_cpu.sh" submit \
    >"$temporary/submit.out" 2>&1; then
  printf 'benchmark submit unexpectedly succeeded off Perlmutter\n' >&2
  exit 1
fi
grep -q 'authoritative only on Perlmutter' "$temporary/submit.out"

printf 'Phase 1 iDMRG benchmark launcher guard tests passed\n'
