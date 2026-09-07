#!/usr/bin/env bash
set -euo pipefail
# Optional Git tree/ref permits testing staged bytes before their commit.
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository="$(git -C "$source_root" rev-parse --show-toplevel)"
project="$(git -C "$source_root" rev-parse --show-prefix)"
project="${project%/}"
revision="${1:-HEAD}"
julia_bin="${JULIA_BIN:-julia}"
mkdir -p "$source_root/tmp"
fixture="$(mktemp -d "$source_root/tmp/pilot-git-delivery.XXXXXX")"
fixture="$(cd "$fixture" && pwd)"
cleanup() {
  case "$fixture" in
    "$source_root"/tmp/pilot-git-delivery.*) rm -rf -- "$fixture" ;;
    *) echo 'ERROR: refusing cleanup outside the test workspace' >&2 ;;
  esac
}
trap cleanup EXIT

# All remotes are disposable local fixtures; no network or scheduler access.
git init --bare -q "$fixture/origin.git"
git init -q -b codex/pilot-delivery "$fixture/publisher"
git -C "$fixture/publisher" config user.name 'Pilot delivery test'
git -C "$fixture/publisher" config user.email 'pilot-delivery@example.invalid'
git -C "$fixture/publisher" config core.autocrlf false
git -C "$fixture/publisher" -c commit.gpgsign=false commit -q --allow-empty -m Baseline
git -C "$fixture/publisher" remote add origin "$fixture/origin.git"
git -C "$fixture/publisher" push -q -u origin codex/pilot-delivery
git clone -q --no-checkout --branch codex/pilot-delivery "$fixture/origin.git" "$fixture/receiver"
git -C "$fixture/receiver" sparse-checkout init --cone
git -C "$fixture/receiver" sparse-checkout set "$project"
git -C "$fixture/receiver" read-tree -mu HEAD
[[ ! -e "$fixture/receiver/$project/configs/mpskit_solver_pilot_active_control.ref" ]]

# Export only Git objects, so ignored local controls/data cannot hide omissions.
git -C "$repository" archive "$revision" "$project" | tar -xf - -C "$fixture/publisher"
git -C "$fixture/publisher" add -- "$project"
git -C "$fixture/publisher" -c commit.gpgsign=false commit -q -m 'Deliver pilot'
git -C "$fixture/publisher" push -q
git -C "$fixture/receiver" pull -q --ff-only
pulled="$fixture/receiver/$project"
[[ ! -e "$pulled/output" ]]
[[ -z "$(git -C "$fixture/receiver" status --porcelain)" ]]
mapfile -t active < <(sed 's/\r$//' "$pulled/configs/mpskit_solver_pilot_active_control.ref")
[[ ${#active[@]} == 2 && "${active[0]}" == configs/controls/*.toml ]]
control="$pulled/${active[0]}"
[[ "$(sha256sum "$control" | awk '{print $1}')" == "${active[1]}" ]]

# Real source hashing must pass; full validation must still require tensor data.
"$julia_bin" --startup-file=no "$pulled/scripts/audit_project_context.jl" \
  --source-export "$control" >"$fixture/context.log" 2>&1
grep -q 'source_export_hash_result: MATCH' "$fixture/context.log"
if "$julia_bin" --startup-file=no "$pulled/scripts/validate_mpskit_solver_pilot.jl" \
    "$control" >"$fixture/missing-data.log" 2>&1; then
  echo 'ERROR: full validation accepted a checkout without scientific data' >&2
  exit 1
fi
grep -q 'pilot input hash mismatch: .*output' "$fixture/missing-data.log"
[[ ! -e "$pulled/output" ]]

# Julia/Slurm operations are mocked inside this separate launcher regression.
bash "$pulled/test/test_solver_pilot_launcher.sh"
echo 'Git delivery: local push/pull into a clean sparse checkout delivers the control and matching source; missing tensor data still blocks full validation.'
