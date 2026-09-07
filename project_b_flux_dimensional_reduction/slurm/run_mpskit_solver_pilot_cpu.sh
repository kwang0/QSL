#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/slurm/lib/project_b_resources.sh"
julia_bin="${JULIA_BIN:-julia}"
root="$project_root/output/mpskit_solver_pilot_jobs"
control_ref="$project_root/configs/mpskit_solver_pilot_active_control.ref"
worker="$project_root/slurm/run_mpskit_solver_pilot_job.sh"
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_perlmutter() {
  [[ "$(hostname -f 2>/dev/null || hostname)" == *perlmutter* && "${PSCRATCH:-}" == /pscratch/* ]] ||
    die 'this action must be run manually on Perlmutter'
}
latest() {
  local f id best=0 directory=""
  [[ -d "$root" ]] || die 'no pilot jobs recorded'
  while IFS= read -r f; do
    id="$(awk -F '\t' 'NR==2 {print $1}' "$f")"
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    if ((id>best)); then best="$id"; directory="$(dirname "$f")"; fi
  done < <(find "$root" -name job.tsv -type f)
  [[ -n "$directory" ]] || die 'no pilot job ID'
  printf '%s\n' "$directory"
}
action="${1:-}"
case "$action" in
  preflight|plan|submit)
    [[ $# -le 2 ]] || die 'usage: preflight|plan|submit [CONTROL]'
    if [[ $# == 2 ]]; then
      control="$2"
    else
      [[ -f "$control_ref" ]] || die 'missing active pilot control reference; sync configs and the sealed control'
      mapfile -t reference < <(sed 's/\r$//' "$control_ref")
      [[ ${#reference[@]} == 2 && "${reference[1]}" =~ ^[0-9a-f]{64}$ ]] || die 'malformed pilot control reference'
      control="$project_root/${reference[0]}"
      [[ -f "$control" ]] || die "missing sealed control: $control"
      [[ "$(sha256sum "$control" | awk '{print $1}')" == "${reference[1]}" ]] || die 'active pilot control hash mismatch'
    fi
    control="$(cd "$(dirname "$control")" && pwd)/$(basename "$control")"
    if [[ "$action" == preflight ]]; then
      require_perlmutter
      printf '\n[1/4] Verify source export and project context\n'
      "$julia_bin" --startup-file=no "$project_root/scripts/audit_project_context.jl" --source-export "$control"
      printf '\n[2/4] Reconcile all Project B accounting in bounded date windows\n'
      pb_reconcile "$project_root"
      printf '\n[3/4] Verify the returned candidate and checkpoints 52 and 60\n'
      "$julia_bin" --startup-file=no --project="$project_root" \
        "$project_root/scripts/audit_yc8_bridge_checkpoints.jl" --control "$control"
      printf '\n[4/4] Run the full live plan and copied-worker executable checks\n'
      bash "${BASH_SOURCE[0]}" plan "$control"
      printf '\nPREFLIGHT PASSED. No job submitted. The guarded submit command is ready.\n'
      exit 0
    fi
    live=false; authority=local
    if [[ "$(hostname -f 2>/dev/null || hostname)" == *perlmutter* ]]; then live=true; authority=live; fi
    [[ "$action" != submit ]] || { require_perlmutter; pb_submission_lock "$project_root"; }
    options=(); [[ "$live" != true ]] || options+=(--live)
    printf 'Validating pilot control and required evidence...\n'
    validation="$("$julia_bin" --startup-file=no "$project_root/scripts/validate_mpskit_solver_pilot.jl" "$control" "${options[@]}")"
    IFS=$'\t' read -r hash forecast cpus step threads memory time_limit pretimeout <<<"$validation"
    pb_guard "$project_root" "$forecast" "$authority"
    printf 'Running copied-worker preflight; Julia may compile the tiny solver checks on first use.\n'
    tmp="$(mktemp -d)"
    cp "$worker" "$tmp/worker.sh"
    if ! bash "$tmp/worker.sh" preflight "$project_root" "$control" "$hash" "$tmp" "$julia_bin"; then
      rm -r "$tmp"; die 'copied worker preflight failed'
    fi
    rm -r "$tmp"
    if [[ -d "$root" ]] && find "$root" -name control.sha256 -type f -exec cat {} + | grep -qx "$hash"; then
      die 'this immutable control has already been submitted'
    fi
    printf 'Pilot: VUMPS at 0.15; matched VUMPS and GradientGrassmann at 0.2, all from accepted chi512 parent.\n'
    printf 'Resources: %s logical CPUs, %s step CPUs, %s Julia threads, %s, %s; %.8f node-hours.\n' "$cpus" "$step" "$threads" "$memory" "$time_limit" "$forecast"
    printf 'Control: %s\nSHA-256: %s\nAuthority: %s\n' "$control" "$hash" "$authority"
    printf 'States and tensor checkpoints: scratch. Scalar histories, analyses, logs and accounting: project.\n'
    printf 'Results remain diagnostic. No automatic promotion or flux advance.\n'
    [[ "$action" == submit ]] || exit 0
    pb_guard "$project_root" "$forecast" live
    run_dir="$root/$(date -u +%Y%m%dT%H%M%SZ)_${hash:0:12}"
    [[ ! -e "$run_dir" ]] || die 'run package exists'
    mkdir -p "$run_dir/logs"
    cp "$control" "$run_dir/control.snapshot.toml"
    printf '%s\n' "$hash" >"$run_dir/control.sha256"
    raw="$(sbatch --parsable --job-name=pb1-solver-pilot --account="${PHASE1_ACCOUNT:-m4863}" \
      --constraint=cpu --qos=shared --nodes=1 --ntasks=1 --cpus-per-task="$cpus" --mem="$memory" \
      --time="$time_limit" --licenses=scratch --signal="B:USR1@$pretimeout" --chdir="$project_root" \
      --output="$run_dir/logs/pilot-%j.out" --export=ALL \
      "$worker" run "$project_root" "$run_dir/control.snapshot.toml" "$hash" "$run_dir" "$julia_bin")"
    id="${raw%%;*}"; [[ "$id" =~ ^[0-9]+$ ]] || die "invalid Slurm ID: $raw"
    printf 'job_id\tcontrol_sha256\tforecast_node_hours\n%s\t%s\t%s\n' "$id" "$hash" "$forecast" >"$run_dir/job.tsv"
    printf 'Submitted pilot %s; run package %s\n' "$id" "$run_dir"
    ;;
  status)
    require_perlmutter; run_dir="$(latest)"
    id="$(awk -F '\t' 'NR==2 {print $1}' "$run_dir/job.tsv")"
    squeue -j "$id" 2>/dev/null || true
    sacct -j "$id" -P --format=JobIDRaw,State,ElapsedRaw,NNodes,NCPUS,MaxRSS,ReqMem,ExitCode
    ;;
  reconcile)
    require_perlmutter
    pb_reconcile "$project_root"
    ;;
  analyze)
    run_dir="$(latest)"
    for stage in baseline_vumps difficult_vumps difficult_gradient; do
      if [[ -f "$run_dir/analysis_$stage.toml" ]]; then
        cat "$run_dir/analysis_$stage.toml"
      else
        printf '%s: common analysis unavailable; inspect the log and retained scratch payload.\n' "$stage"
      fi
    done
    ;;
  *) die 'usage: run_mpskit_solver_pilot_cpu.sh preflight|plan|submit [CONTROL] | status|reconcile|analyze' ;;
esac
