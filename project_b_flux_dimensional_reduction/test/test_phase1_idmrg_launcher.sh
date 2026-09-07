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

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi
}
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
printf 'immutable bridge fixture\n' >"$fixture/bridge.h5"
bridge_sha="$(hash_file "$fixture/bridge.h5" | awk '{print $1}')"
idmrg_manifest_sha="$(hash_file "$project_root/idmrg/Manifest.toml" | awk '{print $1}')"
solver_module_sha="$(hash_file "$project_root/idmrg/src/ProjectBIDMRG.jl" | awk '{print $1}')"
root_manifest_sha="$(hash_file "$project_root/Manifest.toml" | awk '{print $1}')"
analyzer_sha="$(hash_file "$project_root/scripts/analyze_phase1_idmrg_result.jl" | awk '{print $1}')"
launcher_sha="$(hash_file "$project_root/slurm/run_idmrg_cpu.sh" | awk '{print $1}')"
decision_sha="$(hash_file "$project_root/docs/PHASE1_IDMRG_LIBRARY_DECISION.md" | awk '{print $1}')"
working_policy_sha="$(hash_file \
  "$project_root/configs/phase1_idmrg_working_convergence.toml" | awk '{print $1}')"

sed \
  -e "s|BRIDGE_SHA|$bridge_sha|" \
  -e "s|PARENT_PATH|$fixture/parent.h5|" \
  -e "s|IDMRG_MANIFEST_SHA|$idmrg_manifest_sha|" \
  -e "s|SOLVER_MODULE_SHA|$solver_module_sha|" \
  -e "s|ROOT_MANIFEST_SHA|$root_manifest_sha|" \
  -e "s|ANALYZER_SHA|$analyzer_sha|" \
  -e "s|LAUNCHER_SHA|$launcher_sha|" \
  -e "s|DECISION_SHA|$decision_sha|" \
  "$project_root/test/fixtures/phase1_idmrg_control.toml.in" \
  >"$fixture/control.toml"

output="$(JULIA_BIN="$julia_bin" bash "$project_root/slurm/run_idmrg_cpu.sh" plan \
  "$fixture/control.toml")"
grep -q 'LOCAL STRUCTURAL PLAN ONLY' <<<"$output"
grep -q 'automatic submission/advance: disabled' <<<"$output"
grep -q 'maximum forecast charge: 6.0 node-hours' <<<"$output"
grep -q 'account: m4863' <<<"$output"
grep -q 'startup source: immutable bridge only; no prior checkpoint' <<<"$output"
grep -q 'job 57452187 checkpoints required: no' <<<"$output"
grep -q 'submission authorization: literal submit command' <<<"$output"

sed \
  -e '/defined_before_run = true/a\
criterion_profile = "phase1_exploratory_working_20260824"\
criterion_selected_after_job_id = "57500598"\
criterion_policy_path = "configs/phase1_idmrg_working_convergence.toml"\
criterion_policy_sha256 = "WORKING_POLICY_SHA"' \
  -e 's/environment_tolerance = 1.0e-8/environment_tolerance = 1.0e-5/' \
  -e 's/energy_density_span_tolerance = 1.0e-9/energy_density_span_tolerance = 1.0e-8/' \
  "$fixture/control.toml" >"$fixture/working-control-unpinned.toml"
sed -e "s/WORKING_POLICY_SHA/$working_policy_sha/" \
  "$fixture/working-control-unpinned.toml" >"$fixture/working-control.toml"
working_output="$(JULIA_BIN="$julia_bin" bash "$project_root/slurm/run_idmrg_cpu.sh" plan \
  "$fixture/working-control.toml")"
grep -q 'LOCAL STRUCTURAL PLAN ONLY' <<<"$working_output"

sed \
  -e 's/environment_tolerance = 1.0e-8/environment_tolerance = 1.0e-5/' \
  -e 's/energy_density_span_tolerance = 1.0e-9/energy_density_span_tolerance = 1.0e-8/' \
  "$fixture/control.toml" >"$fixture/unlabeled-working-control.toml"
if JULIA_BIN="$julia_bin" bash "$project_root/slurm/run_idmrg_cpu.sh" plan \
    "$fixture/unlabeled-working-control.toml" >"$fixture/unlabeled.out" 2>&1; then
  printf 'unlabeled working convergence thresholds unexpectedly passed\n' >&2
  exit 1
fi
grep -q 'working native thresholds require the pinned criterion profile' \
  "$fixture/unlabeled.out"

if grep -q 'PROJECT_B_IDMRG_SUBMIT_AUTHORIZED' \
    "$project_root/slurm/run_idmrg_cpu.sh"; then
  printf 'launcher still requires the redundant submit acknowledgement\n' >&2
  exit 1
fi
grep -Fq '"$project_root/slurm/run_idmrg_job.sh" run "$project_root" "$control_path" "$result_path"' \
  "$project_root/slurm/run_idmrg_cpu.sh"
grep -Fq -- '--cpus-per-task="$allocation_cpus"' \
  "$project_root/slurm/run_idmrg_cpu.sh"
grep -Fq -- 'exec srun --exact --exclusive --nodes=1 --ntasks=1 --cpus-per-task="$step_cpus" --cpu-bind=cores' \
  "$project_root/slurm/run_idmrg_job.sh"

if JULIA_BIN="$julia_bin" PHASE1_ACCOUNT=m1234 \
    bash "$project_root/slurm/run_idmrg_cpu.sh" submit "$fixture/control.toml" \
    >"$fixture/submit.out" 2>&1; then
  printf 'submit unexpectedly succeeded off Perlmutter\n' >&2
  exit 1
fi
grep -q 'authoritative only on Perlmutter' "$fixture/submit.out"

printf 'tampered\n' >>"$fixture/bridge.h5"
if JULIA_BIN="$julia_bin" bash "$project_root/slurm/run_idmrg_cpu.sh" plan \
    "$fixture/control.toml" >"$fixture/tamper.out" 2>&1; then
  printf 'tampered bridge unexpectedly passed\n' >&2
  exit 1
fi
grep -q 'bridge SHA-256 mismatch' "$fixture/tamper.out"

printf 'Phase 1 iDMRG launcher guard tests passed\n'
