#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_bin="$project_dir/test/fixtures/phase1_launcher"
launcher="$project_dir/slurm/run_scan_cpu.sh"
config="$project_dir/configs/phase1_yc8_1_forward_chi128.toml"
temporary_root="$(mktemp -d)"
trap 'rm -rf "$temporary_root"' EXIT

staged_launcher="$temporary_root/run_scan_cpu.sh"
run_dir="$temporary_root/run"
mock_srun_args="$temporary_root/srun.args"
mkdir -p "$run_dir"
cp "$launcher" "$staged_launcher"

if command -v sha256sum >/dev/null 2>&1; then
  config_sha="$(sha256sum "$config" | awk '{ print $1 }')"
else
  config_sha="$(shasum -a 256 "$config" | awk '{ print $1 }')"
fi

PATH="$fixture_bin:$PATH" \
MOCK_SRUN_ARGS_FILE="$mock_srun_args" \
PHASE1_JULIA=julia \
PHASE1_GNU_TIME="$fixture_bin/time" \
SLURM_JOB_ID=123 \
SLURM_CPUS_PER_TASK=5 \
  bash "$staged_launcher" _run "$config" "$config_sha" "$run_dir" "$project_dir"

grep -Fqx -- "--project=$project_dir" "$mock_srun_args"
grep -Fqx -- "$project_dir/scripts/run_scan.jl" "$mock_srun_args"
grep -Fqx -- "PROJECT_DIR=$project_dir" "$run_dir/worker.env"
grep -Fqx -- 'exit_code=0' "$run_dir/job.result"

cancel_root="$temporary_root/cancel-runs"
cancel_run="$cancel_root/test-run"
cancel_log="$cancel_run/logs/scan-456.out"
mock_scancel_args="$temporary_root/scancel.args"
real_julia="$(command -v julia)"
mkdir -p "$cancel_run/logs"
printf 'job_id\tphase\n456\t1\n' >"$cancel_run/job.tsv"
cat >"$cancel_log" <<'EOF'
Point 3: branch=primary_forward, theta/pi=0.25, chi=128
VUMPS iteration 39: chi=128 residual=8.400000e-05 target=1.000e-05 time=1.0s
VUMPS iteration 40: chi=128 residual=8.500000e-05 target=1.000e-05 time=1.0s
EOF

PATH="$fixture_bin:$PATH" \
MOCK_SCANCEL_ARGS_FILE="$mock_scancel_args" \
MOCK_SQUEUE_STATE=RUNNING \
PHASE1_RUN_ROOT="$cancel_root" \
PHASE1_JULIA="$real_julia" \
  bash "$launcher" cancel-plateau test-run

grep -Fqx -- '456' "$mock_scancel_args"
grep -Fq -- 'classification = "operator_confirmed_numerical_plateau"' \
  "$cancel_run/termination.toml"
grep -Fq -- 'continuation_accepted = false' "$cancel_run/termination.toml"
grep -Fq -- 'physical_endpoint = false' "$cancel_run/termination.toml"
grep -Fq -- 'last_outer_iteration = 40' "$cancel_run/termination.toml"
grep -Fq -- 'last_theta_over_pi = 0.25' "$cancel_run/termination.toml"

printf '%s\n' 'phase1 staged-launcher regression: ok'
