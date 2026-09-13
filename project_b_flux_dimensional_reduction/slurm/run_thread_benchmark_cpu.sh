#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/slurm/lib/project_b_resources.sh"
julia_bin="${JULIA_BIN:-julia}"
root="$project_root/output/mpskit_solver_pilot_jobs/thread_benchmark"
worker="$project_root/slurm/run_thread_benchmark_job.sh"
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_perlmutter() {
  [[ "$(hostname -f 2>/dev/null || hostname)" == *perlmutter* && "${PSCRATCH:-}" == /pscratch/* ]] ||
    die 'this action must be run manually on Perlmutter'
}
latest() {
  local f id best=0 directory=""
  [[ -d "$root" ]] || die 'no thread benchmark jobs recorded'
  while IFS= read -r f; do
    id="$(awk -F '\t' 'NR==2 {print $1}' "$f")"
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    if [[ -n "${RUN_ID:-}" ]]; then
      [[ "$id" != "$RUN_ID" ]] || { printf '%s\n' "$(dirname "$f")"; return; }
    elif ((id>best)); then best="$id"; directory="$(dirname "$f")"; fi
  done < <(find "$root" -name job.tsv -type f)
  [[ -n "$directory" ]] || die 'no matching benchmark job ID'
  printf '%s\n' "$directory"
}
action="${1:-}"
case "$action" in
  preflight|plan|submit)
    [[ $# -le 2 ]] || die 'usage: preflight|plan|submit [CONTROL]'
    if [[ $# == 2 ]]; then control="$2"
    else
      ref="$project_root/configs/thread_benchmark_active_control.ref"
      [[ -f "$ref" ]] || die 'missing active thread benchmark reference'
      mapfile -t reference < <(sed 's/\r$//' "$ref")
      [[ ${#reference[@]} == 2 && "${reference[0]}" == configs/controls/*.toml && "${reference[1]}" =~ ^[0-9a-f]{64}$ ]] || die 'malformed active reference'
      control="$project_root/${reference[0]}"
      [[ -f "$control" ]] || die "missing sealed control: $control"
      [[ "$(sha256sum "$control" | awk '{print $1}')" == "${reference[1]}" ]] || die 'active control hash mismatch'
    fi
    control="$(cd "$(dirname "$control")" && pwd)/$(basename "$control")"
    if [[ "$action" == preflight ]]; then
      require_perlmutter
      "$julia_bin" --startup-file=no "$project_root/scripts/audit_project_context.jl"
      pb_reconcile "$project_root"
      bash "${BASH_SOURCE[0]}" plan "$control"
      printf 'PREFLIGHT PASSED. No job submitted.\n'; exit 0
    fi
    authority=local; validation_args=()
    if [[ "$(hostname -f 2>/dev/null || hostname)" == *perlmutter* ]]; then require_perlmutter; authority=live; validation_args=(--live); fi
    [[ "$action" != submit ]] || { require_perlmutter; pb_submission_lock "$project_root"; }
    validation="$("$julia_bin" --startup-file=no "$project_root/scripts/validate_thread_benchmark.jl" "$control" "${validation_args[@]}")"
    IFS=$'\t' read -r hash forecast cpus step memory time_limit pretimeout <<<"$validation"
    pb_guard "$project_root" "$forecast" "$authority"
    tmp="$(mktemp -d)"; cp "$worker" "$tmp/worker.sh"
    if ! bash "$tmp/worker.sh" preflight "$project_root" "$control" "$hash" "$tmp" "$julia_bin"; then
      rm "$tmp/worker.sh"; rmdir "$tmp"; die 'copied worker smoke failed'
    fi
    rm "$tmp/worker.sh"; rmdir "$tmp"
    if [[ -d "$root" ]] && find "$root" -name control.sha256 -type f -exec cat {} + | grep -qx "$hash"; then
      die 'this immutable control already has a submission package'
    fi
    printf 'chi1024 VUMPS timing: Julia/BLAS 2/1, 2/4, 1/8; same rejected theta/pi=0.15 seed.\n'
    printf 'Each setting: 1 warm-up + 3 measured updates. No flux advance or scientific promotion.\n'
    printf 'Resources: %s allocation CPUs, %s step CPUs, %s, %s; %.8f node-hours.\n' "$cpus" "$step" "$memory" "$time_limit" "$forecast"
    [[ "$authority" != local ]] || printf 'Local source plan only: scratch seed presence/hash is deferred to Perlmutter preflight.\n'
    printf 'Control: %s\nSHA-256: %s\nAuthority: %s\nPLAN PASSED\n' "$control" "$hash" "$authority"
    [[ "$action" == submit ]] || exit 0
    pb_guard "$project_root" "$forecast" live
    run_dir="$root/$(date -u +%Y%m%dT%H%M%SZ)_${hash:0:12}"
    [[ ! -e "$run_dir" ]] || die 'run package exists'
    mkdir -p "$run_dir/logs"; cp "$control" "$run_dir/control.snapshot.toml"
    printf '%s\n' "$hash" >"$run_dir/control.sha256"
    raw="$(sbatch --parsable --job-name=pb1-threads --account="${PHASE1_ACCOUNT:-m4863}" \
      --constraint=cpu --qos=shared --nodes=1 --ntasks=1 --cpus-per-task="$cpus" --mem="$memory" \
      --time="$time_limit" --licenses=scratch --signal="B:USR1@$pretimeout" --chdir="$project_root" \
      --output="$run_dir/logs/threads-%j.out" --export=ALL \
      "$worker" run "$project_root" "$run_dir/control.snapshot.toml" "$hash" "$run_dir" "$julia_bin")"
    id="${raw%%;*}"; [[ "$id" =~ ^[0-9]+$ ]] || die "invalid Slurm ID: $raw"
    printf 'job_id\tcontrol_sha256\tforecast_node_hours\n%s\t%s\t%s\n' "$id" "$hash" "$forecast" >"$run_dir/job.tsv"
    printf 'Submitted threading benchmark %s; run package %s\n' "$id" "$run_dir"
    ;;
  status|progress)
    require_perlmutter; run_dir="$(latest)"; id="$(awk -F '\t' 'NR==2 {print $1}' "$run_dir/job.tsv")"
    printf 'Run package: %s\n' "$run_dir"; squeue -j "$id" 2>/dev/null || true
    sacct -j "$id" -P --format=JobIDRaw,State,ElapsedRaw,NNodes,NCPUS,MaxRSS,ReqMem,ExitCode
    [[ "$action" != progress ]] || {
      [[ ! -f "$run_dir/step_exit_codes.tsv" ]] || cat "$run_dir/step_exit_codes.tsv"
      [[ ! -f "$run_dir/logs/threads-$id.out" ]] || tail -n 40 "$run_dir/logs/threads-$id.out"
    }; ;;
  reconcile) require_perlmutter; pb_reconcile "$project_root" ;;
  analyze) "$julia_bin" --startup-file=no "$project_root/scripts/summarize_thread_benchmark.jl" "$(latest)" ;;
  *) die 'usage: run_thread_benchmark_cpu.sh preflight|plan|submit [CONTROL] | status|progress|reconcile|analyze; optional RUN_ID=JOB_ID' ;;
esac
