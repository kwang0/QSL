#!/usr/bin/env bash
# Local shell-only allocation cases plus one copied-worker startup; no Slurm
# commands, scratch writes or numerical solvers are invoked.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/slurm/thread_benchmark/resources.sh"
export SLURM_JOB_ID=fixture SLURM_JOB_NUM_NODES=1
export SLURM_CPUS_PER_TASK=36 SLURM_JOB_CPUS_PER_NODE=36
[[ "$(thread_benchmark_allocation 36 16)" == 36 ]]
export SLURM_CPUS_PER_TASK=34 SLURM_JOB_CPUS_PER_NODE='36(x1)'
[[ "$(thread_benchmark_allocation 36 16)" == 36 ]]
export SLURM_JOB_CPUS_PER_NODE=34
[[ "$(thread_benchmark_allocation 36 16)" == 34 ]]
export SLURM_CPUS_PER_TASK=38 SLURM_JOB_CPUS_PER_NODE=38
if thread_benchmark_allocation 36 16; then echo 'Over-budget allocation accepted' >&2; exit 1; fi
export SLURM_CPUS_PER_TASK=8 SLURM_JOB_CPUS_PER_NODE=36
if thread_benchmark_allocation 36 16; then echo 'Insufficient task CPUs accepted' >&2; exit 1; fi

[[ $# == 3 ]] || { echo 'usage: CONTROL JULIA FRESH_OUTPUT' >&2; exit 2; }
control="$1" julia="$2" output="$3"
[[ ! -e "$output" ]] || exit 2
mkdir -p "$output"
cp "$root/slurm/run_thread_benchmark_job.sh" "$output/copied_worker.sh"
export SLURM_CPUS_PER_TASK=36 SLURM_JOB_CPUS_PER_NODE=36 PSCRATCH=/deliberately-unavailable-benchmark-fixture
hash="$(sha256sum "$control" | awk '{print $1}')"
if bash "$output/copied_worker.sh" run "$root" "$control" "$hash" "$output" "$julia" >"$output/startup.log" 2>&1; then
  echo 'Expected the deliberate scratch guard failure' >&2; exit 1
fi
grep -q 'Allocation accepted: 36 CPUs' "$output/startup.log"
grep -q 'PSCRATCH directory unavailable' "$output/startup.log"
grep -qx 'stage=scratch_validation' "$output/job.result"
grep -qx 'benchmark_complete=false' "$output/job.result"
printf 'Allocation bounds and copied-worker startup diagnostics passed; no numerical work run.\n'
