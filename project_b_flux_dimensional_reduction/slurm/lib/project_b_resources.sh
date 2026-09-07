#!/usr/bin/env bash
# Caller supplies the absolute project root. Never infer it from a copied worker.
pb_forecast() {
  "${JULIA_BIN:-julia}" --startup-file=no "$1/scripts/project_b_accounting.jl" forecast "${@:2}"
}
pb_guard() {
  local root="$1" forecast="$2" authority="${3:-live}"
  if [[ "$authority" == live ]]; then
    "${JULIA_BIN:-julia}" --startup-file=no "$root/scripts/project_b_accounting.jl" guard --live "$forecast"
  else
    "${JULIA_BIN:-julia}" --startup-file=no "$root/scripts/project_b_accounting.jl" guard "$forecast"
  fi
}
pb_submission_lock() {
  local root="$1"
  mkdir -p "$root/output/accounting"
  command -v flock >/dev/null || { echo 'ERROR: flock is required for submission' >&2; return 1; }
  exec {PB_SUBMISSION_LOCK_FD}>"$root/output/accounting/submission.lock"
  flock -n "$PB_SUBMISSION_LOCK_FD" || {
    printf 'ERROR: another Project B submission holds the common lock\n' >&2
    return 1
  }
}
pb_reconcile() {
  "${JULIA_BIN:-julia}" --startup-file=no "$1/scripts/project_b_accounting.jl" reconcile --live
}
