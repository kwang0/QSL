#!/usr/bin/env bash
set -euo pipefail
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$source_root/tmp"
fixture="$(mktemp -d "$source_root/tmp/relaxation-launcher.XXXXXX")"
cleanup() {
  case "$fixture" in "$source_root"/tmp/relaxation-launcher.*) rm -rf -- "$fixture" ;; *) exit 3 ;; esac
}
trap cleanup EXIT
mkdir -p "$fixture/project/slurm/lib" "$fixture/project/configs/controls" "$fixture/bin"
cp "$source_root/slurm/run_relaxation_continuation_cpu.sh" "$source_root/slurm/run_relaxation_continuation_job.sh" "$fixture/project/slurm/"
cp "$source_root/slurm/lib/project_b_resources.sh" "$fixture/project/slurm/lib/"
touch "$fixture/project/Project.toml"
printf 'fixture = true\n' >"$fixture/project/configs/controls/control.toml"
export TEST_HASH="$(sha256sum "$fixture/project/configs/controls/control.toml" | awk '{print $1}')"
printf 'configs/controls/control.toml\r\n%s\r\n' "$TEST_HASH" >"$fixture/project/configs/relaxation_continuation_active_control.ref"
cat >"$fixture/bin/hostname" <<'EOF'
#!/usr/bin/env bash
echo perlmutter.test
EOF
cat >"$fixture/bin/julia" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  case "$arg" in
    */audit_project_context.jl) operation=context ;;
    */project_b_accounting.jl) operation=accounting ;;
    */validate_relaxation_continuation.jl) operation=validation ;;
    */relaxation_continuation.jl) operation=kernel ;;
    */relaxation_analysis.jl) operation=analysis ;;
    */summarize_relaxation_continuation.jl) operation=summary ;;
  esac
done
printf '%s\n' "$operation" >>"$TEST_CALLS"
[[ "${FAIL_AT:-}" != "$operation" ]] || exit 23
if [[ "$operation" == validation ]]; then
  printf '%s\t1.40625\t10\t4\t2\t16G\t36:00:00\t1800\n' "$TEST_HASH"
fi
EOF
cat >"$fixture/bin/sbatch" <<'EOF'
#!/usr/bin/env bash
echo submission >>"$TEST_CALLS"
printf '%s\n' "$*" >"$TEST_SUBMISSION"
echo 999100
EOF
cat >"$fixture/bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$fixture/bin/squeue" <<'EOF'
#!/usr/bin/env bash
printf 'queue %s\n' "$*"
EOF
cat >"$fixture/bin/sacct" <<'EOF'
#!/usr/bin/env bash
printf 'accounting %s\n' "$*"
EOF
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH" PSCRATCH=/pscratch/test-fixture JULIA_BIN="$fixture/bin/julia"
export TEST_CALLS="$fixture/calls" TEST_SUBMISSION="$fixture/submission"
launcher="$fixture/project/slurm/run_relaxation_continuation_cpu.sh"
for failure in context accounting validation kernel analysis; do
  : >"$TEST_CALLS"
  if FAIL_AT="$failure" bash "$launcher" preflight >"$fixture/log" 2>&1; then
    echo "ERROR: preflight ignored $failure" >&2; exit 1
  fi
  [[ "$(tail -n 1 "$TEST_CALLS")" == "$failure" ]]
  ! grep -q submission "$TEST_CALLS"
  ! grep -q 'PREFLIGHT PASSED' "$fixture/log"
done
: >"$TEST_CALLS"
bash "$launcher" preflight >"$fixture/log" 2>&1
grep -q 'PREFLIGHT PASSED' "$fixture/log"
grep -q 'Copied relaxation worker preflight passed' "$fixture/log"
! grep -q submission "$TEST_CALLS"

# Guarded submit repeats validation, holds the common lock and reserves the pinned resources.
bash "$launcher" submit >"$fixture/log" 2>&1
[[ "$(grep -c '^submission$' "$TEST_CALLS")" == 1 ]]
grep -q -- '--job-name=pb1-relaxation' "$TEST_SUBMISSION"
grep -q -- '--cpus-per-task=10 --mem=16G --time=36:00:00' "$TEST_SUBMISSION"
grep -q -- '--licenses=scratch' "$TEST_SUBMISSION"
if bash "$launcher" submit >"$fixture/log" 2>&1; then echo 'duplicate submit accepted' >&2; exit 1; fi
[[ "$(grep -c '^submission$' "$TEST_CALLS")" == 1 ]]
grep -q 'already has a submission package' "$fixture/log"

root="$fixture/project/output/mpskit_solver_pilot_jobs/relaxation"
mkdir -p "$root/old"
printf 'job_id\tcontrol_sha256\tforecast_node_hours\n999000\t%s\t1.40625\n' "$TEST_HASH" >"$root/old/job.tsv"
printf '%s\n' "$root/old" >"$root/latest_run.txt"
bash "$launcher" status >"$fixture/log" 2>&1
grep -q 'queue -j 999100' "$fixture/log"
RUN_ID=999000 bash "$launcher" status >"$fixture/log" 2>&1
grep -q 'queue -j 999000' "$fixture/log"

printf 'tampered\n' >>"$fixture/project/configs/controls/control.toml"
: >"$TEST_CALLS"
if bash "$launcher" preflight >"$fixture/log" 2>&1; then echo 'tampering accepted' >&2; exit 1; fi
[[ ! -s "$TEST_CALLS" ]]
grep -q 'active relaxation control hash mismatch' "$fixture/log"
echo 'Launcher tests pass: failures stop, copied worker executes, submit resources/duplicate guard, greatest job ID, explicit job selection, and tamper rejection.'
