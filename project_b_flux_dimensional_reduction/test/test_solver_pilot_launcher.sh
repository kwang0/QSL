#!/usr/bin/env bash
set -euo pipefail
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
[[ -n "$fixture" && -d "$fixture" ]] || exit 1
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/project/slurm/lib" "$fixture/project/configs" "$fixture/bin"
cp "$source_root/slurm/run_mpskit_solver_pilot_cpu.sh" "$source_root/slurm/run_mpskit_solver_pilot_job.sh" "$fixture/project/slurm/"
cp "$source_root/slurm/lib/project_b_resources.sh" "$fixture/project/slurm/lib/"
touch "$fixture/project/Project.toml"
printf 'test_control = true\n' >"$fixture/project/control.toml"
export TEST_HASH="$(sha256sum "$fixture/project/control.toml" | awk '{print $1}')"
printf 'control.toml\r\n%s\r\n' "$TEST_HASH" >"$fixture/project/configs/mpskit_solver_pilot_active_control.ref"
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
    */audit_yc8_bridge_checkpoints.jl) operation=scratch ;;
    */validate_mpskit_solver_pilot.jl) operation=validation ;;
    */preflight_solver_pilot.jl) operation=kernel ;;
  esac
done
printf '%s\n' "$operation" >>"$TEST_CALLS"
[[ "${FAIL_AT:-}" != "$operation" ]] || exit 23
if [[ "$operation" == validation ]]; then
  printf '%s\t0.46875\t10\t4\t2\t16G\t12:00:00\t1800\n' "$TEST_HASH"
fi
EOF
cat >"$fixture/bin/sbatch" <<'EOF'
#!/usr/bin/env bash
echo 'submission attempted during preflight' >>"$TEST_CALLS"
exit 99
EOF
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH" PSCRATCH=/pscratch/test-fixture
export JULIA_BIN="$fixture/bin/julia" TEST_CALLS="$fixture/calls"
launcher="$fixture/project/slurm/run_mpskit_solver_pilot_cpu.sh"
for failure in context accounting scratch validation kernel; do
  : >"$TEST_CALLS"
  if FAIL_AT="$failure" bash "$launcher" preflight >"$fixture/log" 2>&1; then
    echo "ERROR: preflight ignored failure at $failure" >&2; exit 1
  fi
  [[ "$(tail -n 1 "$TEST_CALLS")" == "$failure" ]]
  ! grep -q 'submission attempted' "$TEST_CALLS"
  ! grep -q 'PREFLIGHT PASSED' "$fixture/log"
done
: >"$TEST_CALLS"
bash "$launcher" preflight >"$fixture/log" 2>&1
grep -q 'PREFLIGHT PASSED' "$fixture/log"
grep -q 'Copied pilot worker preflight passed' "$fixture/log"
[[ "$(grep -c '^validation$' "$TEST_CALLS")" == 2 ]]
! grep -q 'submission attempted' "$TEST_CALLS"
printf 'tampered\n' >>"$fixture/project/control.toml"
: >"$TEST_CALLS"
if bash "$launcher" preflight >"$fixture/log" 2>&1; then
  echo 'ERROR: active control tampering passed' >&2; exit 1
fi
[[ ! -s "$TEST_CALLS" ]]
grep -q 'active pilot control hash mismatch' "$fixture/log"
echo 'Pilot launcher: five failure stages stop, copied worker runs, active hashes enforce integrity, no preflight submits.'
