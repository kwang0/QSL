#!/usr/bin/env bash
set -euo pipefail
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository="$(git -C "$source_root" rev-parse --show-toplevel)"
project="$(git -C "$source_root" rev-parse --show-prefix)"; project="${project%/}"
revision="${1:-HEAD}"; julia_bin="${JULIA_BIN:-julia}"
mkdir -p "$source_root/tmp"
fixture="$(mktemp -d "$source_root/tmp/roundtrip-delivery.XXXXXX")"
cleanup() {
  case "$fixture" in "$source_root"/tmp/roundtrip-delivery.*) rm -rf -- "$fixture" ;; *) exit 3 ;; esac
}
trap cleanup EXIT
git init --bare -q "$fixture/origin.git"
git init -q -b codex/roundtrip-delivery "$fixture/publisher"
git -C "$fixture/publisher" config user.name 'Diagnostic delivery test'
git -C "$fixture/publisher" config user.email 'delivery@example.invalid'
git -C "$fixture/publisher" config core.autocrlf false
git -C "$fixture/publisher" -c commit.gpgsign=false commit -q --allow-empty -m Baseline
git -C "$fixture/publisher" remote add origin "$fixture/origin.git"
git -C "$fixture/publisher" push -q -u origin codex/roundtrip-delivery
git clone -q --no-checkout --branch codex/roundtrip-delivery "$fixture/origin.git" "$fixture/receiver"
git -C "$fixture/receiver" sparse-checkout init --cone
git -C "$fixture/receiver" sparse-checkout set "$project"
git -C "$fixture/receiver" read-tree -mu HEAD
git -C "$repository" archive "$revision" "$project" | tar -xf - -C "$fixture/publisher"
git -C "$fixture/publisher" add -- "$project"
git -C "$fixture/publisher" -c commit.gpgsign=false commit -q -m 'Deliver roundtrip trial'
git -C "$fixture/publisher" push -q
git -C "$fixture/receiver" pull -q --ff-only
pulled="$fixture/receiver/$project"
[[ ! -e "$pulled/output" && -z "$(git -C "$fixture/receiver" status --porcelain)" ]]
mapfile -t active < <(sed 's/\r$//' "$pulled/configs/roundtrip_continuation_active_control.ref")
[[ ${#active[@]} == 2 && "${active[0]}" == configs/controls/*.toml ]]
control="$pulled/${active[0]}"
[[ "$(sha256sum "$control" | awk '{print $1}')" == "${active[1]}" ]]
"$julia_bin" --startup-file=no "$pulled/scripts/validate_roundtrip_continuation.jl" "$control" --code-only
if "$julia_bin" --startup-file=no "$pulled/scripts/validate_roundtrip_continuation.jl" "$control" >"$fixture/missing.log" 2>&1; then
  echo 'ERROR: full validation accepted missing tensor data' >&2; exit 1
fi
grep -q 'roundtrip input hash mismatch: .*output' "$fixture/missing.log"
[[ ! -e "$pulled/output" ]]
printf '\n# test tampering\n' >>"$pulled/idmrg/roundtrip/Continuation.jl"
if "$julia_bin" --startup-file=no "$pulled/scripts/validate_roundtrip_continuation.jl" "$control" --code-only >"$fixture/tamper.log" 2>&1; then
  echo 'ERROR: modified runtime accepted' >&2; exit 1
fi
grep -q 'roundtrip input hash mismatch' "$fixture/tamper.log"
echo 'Git delivery passes: real push/pull into an empty sparse checkout delivers sealed inputs; missing tensors and changed source fail validation.'
