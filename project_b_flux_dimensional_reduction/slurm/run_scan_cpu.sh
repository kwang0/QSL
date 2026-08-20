#!/bin/bash
#SBATCH --job-name=pb1-scan
#SBATCH --constraint=cpu
#SBATCH --qos=shared
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=24:00:00
#SBATCH --output=output/phase1_jobs/%x-%j.out

# Budget-guarded Phase 1 scan launcher for Perlmutter CPU nodes.
#
# Do not invoke this file directly with sbatch. Use `plan`, then `submit`, or
# the guarded chi-512 `advance`/`advance-submit` state machine; the private
# `_run` entry point verifies the config hash and the live allocation.

set -euo pipefail

readonly LAUNCHER_VERSION="2.5.0"
readonly PROJECT_B_HARD_BUDGET_NODE_HOURS=150
readonly PROJECT_B_AUTOMATIC_SUBMISSION_CAP_NODE_HOURS=140
readonly PHASE1_BUDGET_NODE_HOURS=20
readonly PERLMUTTER_MEMORY_MIB_PER_LOGICAL_CPU=1952
readonly PERLMUTTER_PHYSICAL_CORES_PER_CPU_NODE=128
readonly PHASE1_JULIA_THREADS=2
readonly PHASE1_SLURM_CPUS=4
readonly PHASE1_MEMORY=8G
readonly PHASE1_TIME=24:00:00

PHASE1_ACCOUNT="${PHASE1_ACCOUNT:-m4863}"
PHASE1_QOS="${PHASE1_QOS:-shared}"
PHASE1_JULIA="${PHASE1_JULIA:-julia}"
PHASE1_GNU_TIME="${PHASE1_GNU_TIME:-/usr/bin/time}"
# This non-Phase-1 baseline is the Phase 0 estimate documented on 2026-08-06.
# Replace it with reconciled Phase 0 plus other completed non-Phase-1 work when
# accounting becomes available; tracked Phase 1 charges are added separately.
PROJECT_B_ACCOUNTED_BASELINE_NODE_HOURS="${PROJECT_B_ACCOUNTED_BASELINE_NODE_HOURS:-1.094433}"

initial_script_path="${BASH_SOURCE[0]:-$0}"
script_path="$(cd "$(dirname "$initial_script_path")" && pwd)/$(basename "$initial_script_path")"
project_dir="$(cd "$(dirname "$script_path")/.." && pwd)"
run_root="${PHASE1_RUN_ROOT:-$project_dir/output/phase1_jobs}"
submission_lock_dir=""

die() {
  echo "error: $*" >&2
  exit 1
}

cleanup_submission_lock() {
  if [[ -n "${submission_lock_dir:-}" ]]; then
    rmdir "$submission_lock_dir" 2>/dev/null || true
    submission_lock_dir=""
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

float_add() {
  awk -v left="$1" -v right="$2" 'BEGIN { printf "%.9f", left + right }'
}

float_greater() {
  awk -v left="$1" -v right="$2" 'BEGIN { exit !(left > right) }'
}

validate_nonnegative_number() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "$2 must be a nonnegative decimal, got '$1'"
}

ceil_div() {
  local numerator="$1"
  local denominator="$2"
  echo $(( (numerator + denominator - 1) / denominator ))
}

memory_to_mib() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  raw="${raw//IB/}"
  raw="${raw//B/}"
  raw="${raw%N}"
  raw="${raw%C}"
  case "$raw" in
    *G)
      [[ "${raw%G}" =~ ^[0-9]+$ ]] || die "unsupported memory value: $1"
      echo $(( ${raw%G} * 1024 ))
      ;;
    *M)
      [[ "${raw%M}" =~ ^[0-9]+$ ]] || die "unsupported memory value: $1"
      echo "${raw%M}"
      ;;
    *)
      [[ "$raw" =~ ^[0-9]+$ ]] || die "unsupported memory value: $1"
      echo "$raw"
      ;;
  esac
}

time_to_seconds() {
  local raw="$1"
  local days=0
  local clock="$raw"
  [[ "$raw" != "UNLIMITED" ]] || die "cannot budget an unlimited Slurm job"
  if [[ "$raw" == *-* ]]; then
    days="${raw%%-*}"
    clock="${raw#*-}"
  fi
  local first second third
  IFS=: read -r first second third <<<"$clock"
  if [[ -z "${third:-}" ]]; then
    third="$second"
    second="$first"
    first=0
  fi
  [[ "$days" =~ ^[0-9]+$ && "$first" =~ ^[0-9]+$ && "$second" =~ ^[0-9]+$ && "$third" =~ ^[0-9]+$ ]] ||
    die "unsupported Slurm time value: $raw"
  echo $(( days * 86400 + 10#$first * 3600 + 10#$second * 60 + 10#$third ))
}

node_hours_for_seconds() {
  local logical_cpus="$1"
  local memory="$2"
  local seconds="$3"
  local memory_mib memory_logical unavailable physical
  memory_mib="$(memory_to_mib "$memory")"
  memory_logical="$(ceil_div "$memory_mib" "$PERLMUTTER_MEMORY_MIB_PER_LOGICAL_CPU")"
  unavailable="$logical_cpus"
  (( memory_logical > unavailable )) && unavailable="$memory_logical"
  physical="$(ceil_div "$unavailable" 2)"
  awk -v seconds="$seconds" -v physical="$physical" \
    -v cores="$PERLMUTTER_PHYSICAL_CORES_PER_CPU_NODE" \
    'BEGIN { printf "%.9f", (seconds / 3600.0) * physical / cores }'
}

reservation_node_hours() {
  node_hours_for_seconds "$1" "$2" "$(time_to_seconds "$3")"
}

maximum_effective_logical_cpus() {
  local requested_cpus="$1"
  local memory_mib memory_logical unavailable physical
  memory_mib="$(memory_to_mib "$2")"
  memory_logical="$(ceil_div "$memory_mib" "$PERLMUTTER_MEMORY_MIB_PER_LOGICAL_CPU")"
  unavailable="$requested_cpus"
  (( memory_logical > unavailable )) && unavailable="$memory_logical"
  physical="$(ceil_div "$unavailable" 2)"
  # Any logical-CPU allocation up to this value has the same physical-core
  # Shared-QOS charge already included in reservation_node_hours.
  echo $(( 2 * physical ))
}

validate_effective_cpu_allocation() {
  local effective_cpus="$1"
  [[ "$effective_cpus" =~ ^[0-9]+$ ]] || die \
    "allocation has invalid SLURM_CPUS_PER_TASK=${effective_cpus:-unset}"
  local maximum_effective_cpus
  maximum_effective_cpus="$(maximum_effective_logical_cpus "$PHASE1_SLURM_CPUS" "$PHASE1_MEMORY")"
  (( effective_cpus >= PHASE1_SLURM_CPUS )) || die \
    "allocation has only $effective_cpus task CPUs; at least $PHASE1_SLURM_CPUS are required"
  (( effective_cpus <= maximum_effective_cpus )) || die \
    "allocation has $effective_cpus task CPUs, exceeding the budgeted same-charge maximum $maximum_effective_cpus"
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{ print $1 }'
  else
    die "sha256sum or shasum is required"
  fi
}

validate_project() {
  [[ -f "$project_dir/Project.toml" ]] || die "Project.toml not found under $project_dir"
  [[ -f "$project_dir/scripts/run_scan.jl" ]] || die "run_scan.jl not found under $project_dir"
  [[ "$PHASE1_QOS" == "shared" ]] || die "Phase 1 requires the shared QOS"
  [[ "$PHASE1_ACCOUNT" =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid NERSC account: $PHASE1_ACCOUNT"
  validate_nonnegative_number "$PROJECT_B_ACCOUNTED_BASELINE_NODE_HOURS" \
    "accounted Project B baseline"
}

# Print one tab-separated config record after enforcing the Phase 1 scout
# contract. This uses only Julia's TOML standard library, not the project depot.
config_record() {
  local config_path="$1"
  [[ -f "$config_path" ]] || die "configuration file does not exist: $config_path"
  "$PHASE1_JULIA" --startup-file=no -e '
    using SHA, TOML
    path = abspath(ARGS[1])
    raw = TOML.parsefile(path)
    gettable(name) = haskey(raw, name) ? raw[name] : error("missing [$name]")
    model = gettable("model")
    optimizer = gettable("optimizer")
    scan = gettable("scan")
    runtime = gettable("runtime")
    required(table, key) = haskey(table, key) ? table[key] : error("missing $key")
    circumference = Int(required(model, "circumference"))
    shift = Int(get(model, "shift", 0))
    (circumference, shift) in ((8, 0), (8, 1)) || error("Phase 1 accepts only YC8-0 or YC8-1")
    expected_period = shift == 0 ? 8 : 2
    Int(required(model, "mps_period")) == expected_period || error("Phase 1 requires the minimal MPS period $expected_period")
    lowercase(String(get(model, "twist_gauge", ""))) == "uniform" || error("Phase 1 requires twist_gauge=uniform")
    chi = Int(required(optimizer, "maxdim"))
    64 <= chi <= 512 || error("Phase 1 chi must lie in 64:512")
    tolerance = Float64(required(optimizer, "residual_tol"))
    1e-6 <= tolerance <= 1e-5 || error("Phase 1 scout residual_tol must lie in [1e-6, 1e-5]")
    max_iterations = Int(get(optimizer, "max_iterations", 100))
    max_iterations >= 1 || error("Phase 1 max_iterations must be positive")
    solver_krylov_dimension = Int(get(optimizer, "solver_krylov_dimension", 30))
    solver_krylov_dimension >= 4 || error(
      "Phase 1 solver_krylov_dimension must be at least 4")
    solver_max_iterations = Int(get(optimizer, "solver_max_iterations", 100))
    solver_max_iterations >= 1 || error(
      "Phase 1 solver_max_iterations must be positive")
    record_krylov_diagnostics = Bool(get(optimizer, "record_krylov_diagnostics", false))
    plateau_detection = Bool(get(optimizer, "plateau_detection", false))
    plateau_warmup_iterations = Int(get(optimizer, "plateau_warmup_iterations", 30))
    plateau_patience = Int(get(optimizer, "plateau_patience", 24))
    plateau_min_relative_improvement = Float64(get(
      optimizer, "plateau_min_relative_improvement", 5e-3))
    plateau_warmup_iterations >= 2 || error(
      "Phase 1 plateau_warmup_iterations must be at least 2")
    plateau_patience >= 2 || error("Phase 1 plateau_patience must be at least 2")
    0 < plateau_min_relative_improvement < 1 || error(
      "Phase 1 plateau_min_relative_improvement must lie in (0, 1)")
    Bool(get(optimizer, "require_converged", false)) || error("Phase 1 requires require_converged=true")
    branch = String(required(scan, "branch"))
    preparation = String(required(scan, "preparation"))
    direction = lowercase(String(required(scan, "direction")))
    direction in ("forward", "reverse") || error("Phase 1 direction must be forward or reverse")
    lowercase(String(get(scan, "lineage_policy", ""))) == "strict" || error("Phase 1 requires lineage_policy=strict")
    seed_pattern = String(required(scan, "seed_pattern"))
    random_seed = Int(required(scan, "random_seed"))
    fluxes = Float64.(required(scan, "fluxes_over_pi"))
    sparse_fluxes = shift == 1 ? [0.0, 0.5, 0.75, 0.875, 1.0] : [0.0, 1.0, 1.5, 1.75, 2.0]
    legacy_chi512_campaign = shift == 1 && chi == 512 && direction == "forward" &&
      branch == "primary_forward_chi512_legacy_0p1" &&
      preparation == "independent_theta0_alternating_chi512" &&
      seed_pattern == "alternating" && random_seed == 101
    expected_fluxes = legacy_chi512_campaign ? Float64.(0:10) ./ 10 : sparse_fluxes
    direction == "reverse" && reverse!(expected_fluxes)
    initial_value = String(get(scan, "initial_state_file", ""))
    initial_state = isempty(initial_value) ? "" :
      (isabspath(initial_value) ? normpath(initial_value) :
       normpath(joinpath(dirname(path), initial_value)))
    isempty(initial_state) || isfile(initial_state) || error(
      "initial_state_file does not exist: $initial_state")
    initial_state_sha256 = lowercase(String(get(scan, "initial_state_sha256", "")))
    if isempty(initial_state)
      isempty(initial_state_sha256) || error(
        "initial_state_sha256 cannot be set without initial_state_file")
      length(fluxes) == length(expected_fluxes) && all(isapprox.(fluxes, expected_fluxes; atol=1e-12, rtol=0)) ||
        error("an independently prepared Phase 1 config must use its full documented flux schedule")
    else
      occursin(r"^[0-9a-f]{64}$", initial_state_sha256) || error(
        "a resumed Phase 1 config requires a 64-digit initial_state_sha256")
      actual_initial_sha256 = open(initial_state, "r") do io
        bytes2hex(sha256(io))
      end
      actual_initial_sha256 == initial_state_sha256 || error(
        "initial state SHA-256 mismatch: expected $initial_state_sha256, got $actual_initial_sha256")
      isempty(fluxes) && error("a resumed Phase 1 schedule cannot be empty")
      all(isfinite, fluxes) || error("resumed Phase 1 schedule contains a non-finite flux")
      length(unique(fluxes)) == length(fluxes) || error("resumed Phase 1 schedule contains duplicate fluxes")
      differences = diff(fluxes)
      ordered = direction == "forward" ? all(>(0), differences) : all(<(0), differences)
      ordered || isempty(differences) || error("resumed Phase 1 schedule disagrees with its direction")
      crossing = shift == 1 ? 1.0 : 2.0
      all(theta -> 0.0 <= theta <= crossing, fluxes) || error("resumed Phase 1 flux lies outside the scout interval")
    end
    checkpoint_value = String(get(scan, "optimizer_checkpoint_file", ""))
    optimizer_checkpoint = isempty(checkpoint_value) ? "" :
      (isabspath(checkpoint_value) ? normpath(checkpoint_value) :
       normpath(joinpath(dirname(path), checkpoint_value)))
    optimizer_checkpoint_sha256 = lowercase(String(get(
      scan, "optimizer_checkpoint_sha256", "")))
    if isempty(optimizer_checkpoint)
      isempty(optimizer_checkpoint_sha256) || error(
        "optimizer_checkpoint_sha256 cannot be set without optimizer_checkpoint_file")
    else
      isempty(initial_state) && error(
        "an optimizer checkpoint requires a separate accepted initial_state_file")
      isfile(optimizer_checkpoint) || error(
        "optimizer_checkpoint_file does not exist: $optimizer_checkpoint")
      occursin(r"^[0-9a-f]{64}$", optimizer_checkpoint_sha256) || error(
        "an optimizer checkpoint requires a 64-digit optimizer_checkpoint_sha256")
      actual_checkpoint_sha256 = open(optimizer_checkpoint, "r") do io
        bytes2hex(sha256(io))
      end
      actual_checkpoint_sha256 == optimizer_checkpoint_sha256 || error(
        "optimizer checkpoint SHA-256 mismatch: expected $optimizer_checkpoint_sha256, got $actual_checkpoint_sha256")
      length(fluxes) == 1 || error(
        "an optimizer-checkpoint resume must contain exactly one fixed flux")
    end
    Bool(get(scan, "adaptive_bisection", false)) || error("Phase 1 requires adaptive_bisection=true")
    Bool(get(scan, "save_rejected", false)) || error("Phase 1 requires save_rejected=true")
    require_parent_overlap = Bool(get(scan, "require_parent_overlap", false))
    require_parent_overlap || error("Phase 1 requires the parent-overlap continuity gate")
    minimum_parent_overlap = Float64(get(scan, "minimum_parent_overlap_per_site", NaN))
    0.9 <= minimum_parent_overlap <= 1.0 || error(
      "Phase 1 minimum_parent_overlap_per_site must lie in [0.9, 1.0]")
    parent_overlap_tolerance = Float64(get(scan, "parent_overlap_tolerance", NaN))
    0 < parent_overlap_tolerance <= 1e-6 || error(
      "Phase 1 parent_overlap_tolerance must lie in (0, 1e-6]")
    parent_overlap_krylov_dimension = Int(get(scan, "parent_overlap_krylov_dimension", 0))
    parent_overlap_krylov_dimension >= 4 || error(
      "Phase 1 parent_overlap_krylov_dimension must be at least 4")
    Int(get(runtime, "blas_threads", 0)) == 1 || error("Phase 1 requires blas_threads=1")
    Int(get(runtime, "strided_threads", 0)) == 1 || error("Phase 1 requires strided_threads=1")
    Bool(get(runtime, "threaded_blocksparse", false)) || error("Phase 1 requires threaded_blocksparse=true")
    for (label, value) in (("branch", branch), ("preparation", preparation), ("seed_pattern", seed_pattern))
      occursin(r"^[A-Za-z0-9_.-]+$", value) || error("unsafe $label label: $value")
    end
    geometry = "YC$(circumference)-$(shift)"
    output_value = String(required(runtime, "output_directory"))
    output_directory = isabspath(output_value) ? normpath(output_value) :
      normpath(joinpath(dirname(path), output_value))
    initial_record = isempty(initial_state) ? "independent product state" : initial_state
    initial_sha_record = isempty(initial_state_sha256) ? "none" : initial_state_sha256
    checkpoint_record = isempty(optimizer_checkpoint) ? "none" : optimizer_checkpoint
    checkpoint_sha_record = isempty(optimizer_checkpoint_sha256) ? "none" :
      optimizer_checkpoint_sha256
    println(join((geometry, expected_period, "uniform", branch, preparation, direction,
      seed_pattern, random_seed, chi, join(fluxes, ","), tolerance,
      require_parent_overlap, minimum_parent_overlap, parent_overlap_tolerance,
      parent_overlap_krylov_dimension, output_directory, initial_record,
      initial_sha_record, checkpoint_record, checkpoint_sha_record, max_iterations,
      solver_krylov_dimension,
      solver_max_iterations, record_krylov_diagnostics, plateau_detection,
      plateau_warmup_iterations, plateau_patience,
      plateau_min_relative_improvement, path), "\t"))
  ' "$config_path"
}

active_snapshot() {
  require_command squeue
  require_command scontrol
  [[ -n "${USER:-}" ]] || die "USER is not set"
  local project_total=0 phase1_total=0 ids=""
  local row job_id job_name details cpus nodes memory time_limit contribution
  while IFS='|' read -r job_id job_name; do
    [[ -n "$job_id" ]] || continue
    case "$job_name" in
      pb[0-4]-*|project-b-*) ;;
      *) continue ;;
    esac
    details="$(scontrol show job "$job_id" -o)"
    [[ "$details" =~ NumNodes=([0-9]+) ]] || die "cannot read NumNodes for active Project B job $job_id"
    nodes="${BASH_REMATCH[1]}"
    (( nodes == 1 )) || die "cannot safely budget multi-node active Project B job $job_id"
    [[ "$details" =~ NumCPUs=([0-9]+) ]] || die "cannot read NumCPUs for active Project B job $job_id"
    cpus="${BASH_REMATCH[1]}"
    (( cpus >= 1 )) || die "active Project B job $job_id reports zero CPUs"
    [[ "$details" =~ MinMemoryNode=([^[:space:]]+) ]] || die "cannot read per-node memory for active Project B job $job_id"
    memory="${BASH_REMATCH[1]}"
    [[ "$details" =~ TimeLimit=([^[:space:]]+) ]] || die "cannot read TimeLimit for active Project B job $job_id"
    time_limit="${BASH_REMATCH[1]}"
    contribution="$(reservation_node_hours "$cpus" "$memory" "$time_limit")"
    project_total="$(float_add "$project_total" "$contribution")"
    if [[ "$job_name" == pb1-* ]]; then
      phase1_total="$(float_add "$phase1_total" "$contribution")"
    fi
    ids="${ids}${ids:+,}${job_id}"
  done < <(squeue -h -u "$USER" -o '%i|%j')
  printf '%s|%s|%s\n' "$project_total" "$phase1_total" "$ids"
}

phase1_reconciled_snapshot() {
  local total=0 unreconciled=""
  local job_file run_dir charge_file job_id
  [[ -d "$run_root" ]] || {
    printf '0.000000000|\n'
    return
  }
  while IFS= read -r job_file; do
    run_dir="$(dirname "$job_file")"
    charge_file="$run_dir/charged_node_hours.txt"
    job_id="$(awk -F '\t' 'NR == 2 { print $1 }' "$job_file")"
    [[ -n "$job_id" ]] || die "malformed job record: $job_file"
    if [[ -f "$charge_file" ]]; then
      local charge
      charge="$(tr -d '[:space:]' <"$charge_file")"
      validate_nonnegative_number "$charge" "reconciled charge for job $job_id"
      total="$(float_add "$total" "$charge")"
    else
      unreconciled="${unreconciled}${unreconciled:+,}${job_id}"
    fi
  done < <(find "$run_root" -mindepth 2 -maxdepth 2 -name job.tsv -type f | sort)
  printf '%s|%s\n' "$total" "$unreconciled"
}

print_plan() {
  validate_project
  require_command "$PHASE1_JULIA"
  local config_path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  local record geometry period gauge branch preparation direction seed_pattern random_seed chi fluxes tolerance require_overlap minimum_overlap overlap_tolerance overlap_krylov output initial initial_sha optimizer_checkpoint optimizer_checkpoint_sha max_iterations solver_krylov solver_max_iterations record_krylov plateau_detection plateau_warmup plateau_patience plateau_improvement ignored
  record="$(config_record "$config_path")"
  IFS=$'\t' read -r geometry period gauge branch preparation direction seed_pattern random_seed chi fluxes tolerance require_overlap minimum_overlap overlap_tolerance overlap_krylov output initial initial_sha optimizer_checkpoint optimizer_checkpoint_sha max_iterations solver_krylov solver_max_iterations record_krylov plateau_detection plateau_warmup plateau_patience plateau_improvement ignored <<<"$record"
  local forecast reconciled unreconciled project_active phase1_active active_ids
  local maximum_effective_cpus existing_state_count
  forecast="$(reservation_node_hours "$PHASE1_SLURM_CPUS" "$PHASE1_MEMORY" "$PHASE1_TIME")"
  maximum_effective_cpus="$(maximum_effective_logical_cpus "$PHASE1_SLURM_CPUS" "$PHASE1_MEMORY")"
  existing_state_count=0
  if [[ -d "$output/states" ]]; then
    existing_state_count="$(find "$output/states" -maxdepth 1 -type f -name 'state_*.h5' | wc -l | tr -d '[:space:]')"
  fi
  IFS='|' read -r reconciled unreconciled <<<"$(phase1_reconciled_snapshot)"
  if command -v squeue >/dev/null 2>&1 && command -v scontrol >/dev/null 2>&1; then
    IFS='|' read -r project_active phase1_active active_ids <<<"$(active_snapshot)"
  else
    project_active="unavailable"
    phase1_active="unavailable"
    active_ids="unavailable"
  fi
  cat <<EOF
Phase 1 configuration:          $config_path
Geometry / period:              $geometry / $period
Branch / preparation:           $branch / $preparation
Direction / seed:               $direction / $seed_pattern:$random_seed
Chi / residual tolerance:       $chi / $tolerance
Outer iteration cap:            $max_iterations
Inner Krylov setting:           dimension $solver_krylov, max restarts $solver_max_iterations, record=$record_krylov
Plateau detector:               $plateau_detection (warmup $plateau_warmup, window $plateau_patience, minimum improvement $plateau_improvement)
Parent-overlap continuity gate: $require_overlap (minimum/site $minimum_overlap, eigensolve tol $overlap_tolerance, Krylov $overlap_krylov)
Flux schedule:                  $fluxes
Initial state:                  ${initial:-independent product state}
Initial state SHA-256:          ${initial_sha:-none}
Optimizer checkpoint:          ${optimizer_checkpoint:-none}
Optimizer checkpoint SHA-256:  ${optimizer_checkpoint_sha:-none}
Output directory:               $output
Existing immutable states:      $existing_state_count
Calibrated compute setting:     $PHASE1_JULIA_THREADS Julia threads, $PHASE1_SLURM_CPUS CPUs for the scan step, $PHASE1_MEMORY
Allowed effective allocation:  $PHASE1_SLURM_CPUS-$maximum_effective_cpus logical CPUs at the same charge
Wall-time reservation:          $PHASE1_TIME
New worst-case reservation:     $forecast node-hours

Non-Phase-1 accounted baseline: $PROJECT_B_ACCOUNTED_BASELINE_NODE_HOURS node-hours
Reconciled Phase 1 charges:     $reconciled node-hours
Unreconciled Phase 1 job IDs:   ${unreconciled:-none}
Active Project B reservation:   $project_active node-hours
Active Phase 1 reservation:     $phase1_active node-hours
Active Project B job IDs:       ${active_ids:-none}

Phase 1 ceiling:                $PHASE1_BUDGET_NODE_HOURS node-hours
Automatic submission stop:      $PROJECT_B_AUTOMATIC_SUBMISSION_CAP_NODE_HOURS node-hours
Project B hard limit:           $PROJECT_B_HARD_BUDGET_NODE_HOURS node-hours
EOF
  [[ "$project_active" != "unavailable" ]] || cat <<EOF

The scheduler is unavailable here. Planning is still valid, but submission is
only allowed where squeue and scontrol can prove the active Project B reserve.
EOF
}

submit_scan() {
  validate_project
  require_command "$PHASE1_JULIA"
  require_command sbatch
  require_command squeue
  require_command scontrol
  local config_path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  local record geometry period gauge branch preparation direction seed_pattern random_seed chi fluxes tolerance require_overlap minimum_overlap overlap_tolerance overlap_krylov output initial initial_sha optimizer_checkpoint optimizer_checkpoint_sha max_iterations solver_krylov solver_max_iterations record_krylov plateau_detection plateau_warmup plateau_patience plateau_improvement ignored
  record="$(config_record "$config_path")"
  IFS=$'\t' read -r geometry period gauge branch preparation direction seed_pattern random_seed chi fluxes tolerance require_overlap minimum_overlap overlap_tolerance overlap_krylov output initial initial_sha optimizer_checkpoint optimizer_checkpoint_sha max_iterations solver_krylov solver_max_iterations record_krylov plateau_detection plateau_warmup plateau_patience plateau_improvement ignored <<<"$record"

  local existing_state=""
  if [[ -d "$output/states" ]]; then
    existing_state="$(find "$output/states" -maxdepth 1 -type f -name 'state_*.h5' -print -quit)"
  fi
  [[ -z "$existing_state" ]] || die \
    "refusing duplicate Phase 1 submission: output directory $output already contains immutable state artifacts (for example $existing_state); inspect the completed/bracketed branch, or use a distinct output directory for an explicit resume"

  mkdir -p "$run_root"
  submission_lock_dir="$run_root/.submission-lock"
  mkdir "$submission_lock_dir" 2>/dev/null || die \
    "another Phase 1 submission is being budget-checked; if no submit process is running, remove the stale empty directory $submission_lock_dir"
  trap cleanup_submission_lock EXIT

  local project_active phase1_active active_ids reconciled unreconciled forecast
  IFS='|' read -r project_active phase1_active active_ids <<<"$(active_snapshot)"
  IFS='|' read -r reconciled unreconciled <<<"$(phase1_reconciled_snapshot)"
  [[ -z "$unreconciled" ]] || die \
    "refusing submission: Phase 1 job(s) $unreconciled are not reconciled; wait for a terminal state and run reconcile"
  float_greater "$phase1_active" 0 && die \
    "refusing submission: Phase 1 already has an active reservation ($phase1_active node-hours)"
  forecast="$(reservation_node_hours "$PHASE1_SLURM_CPUS" "$PHASE1_MEMORY" "$PHASE1_TIME")"

  local phase1_projected project_spent project_projected
  phase1_projected="$(float_add "$reconciled" "$phase1_active")"
  phase1_projected="$(float_add "$phase1_projected" "$forecast")"
  project_spent="$(float_add "$PROJECT_B_ACCOUNTED_BASELINE_NODE_HOURS" "$reconciled")"
  project_projected="$(float_add "$project_spent" "$project_active")"
  project_projected="$(float_add "$project_projected" "$forecast")"
  float_greater "$phase1_projected" "$PHASE1_BUDGET_NODE_HOURS" && die \
    "refusing submission: Phase 1 could reach $phase1_projected node-hours (cap $PHASE1_BUDGET_NODE_HOURS)"
  float_greater "$project_projected" "$PROJECT_B_HARD_BUDGET_NODE_HOURS" && die \
    "refusing submission: Project B could reach $project_projected node-hours (hard limit $PROJECT_B_HARD_BUDGET_NODE_HOURS)"
  float_greater "$project_projected" "$PROJECT_B_AUTOMATIC_SUBMISSION_CAP_NODE_HOURS" && die \
    "refusing automatic submission: Project B could reach $project_projected node-hours, crossing the protected-contingency stop at $PROJECT_B_AUTOMATIC_SUBMISSION_CAP_NODE_HOURS"

  local run_id="${2:-$(date -u +%Y%m%dT%H%M%SZ)-$(printf '%s' "$geometry-$branch-$chi" | tr '[:upper:]' '[:lower:]')}"
  [[ "$run_id" =~ ^[A-Za-z0-9_.-]+$ ]] || die "run id contains unsafe characters: $run_id"
  local run_dir="$run_root/$run_id"
  [[ ! -e "$run_dir" ]] || die "run directory already exists: $run_dir"
  mkdir -p "$run_dir/logs" "$run_dir/metrics"
  local config_sha
  config_sha="$(sha256_file "$config_path")"
  cp "$config_path" "$run_dir/config.snapshot.toml"
  printf '%s\n' "$config_sha" >"$run_dir/config.sha256"
  printf '%s\n' "$forecast" >"$run_dir/forecast_node_hours.txt"
  {
    printf 'LAUNCHER_VERSION=%q\n' "$LAUNCHER_VERSION"
    printf 'PROJECT_DIR=%q\n' "$project_dir"
    printf 'PROJECT_B_ACCOUNTED_BASELINE_NODE_HOURS=%q\n' "$PROJECT_B_ACCOUNTED_BASELINE_NODE_HOURS"
    printf 'PHASE1_ACCOUNT=%q\n' "$PHASE1_ACCOUNT"
    printf 'PHASE1_QOS=%q\n' "$PHASE1_QOS"
    printf 'PHASE1_JULIA=%q\n' "$PHASE1_JULIA"
    printf 'PHASE1_GNU_TIME=%q\n' "$PHASE1_GNU_TIME"
    printf 'CONFIG_PATH=%q\n' "$config_path"
    printf 'CONFIG_SHA256=%q\n' "$config_sha"
    printf 'INITIAL_STATE_SHA256=%q\n' "$initial_sha"
    printf 'OPTIMIZER_CHECKPOINT_SHA256=%q\n' "$optimizer_checkpoint_sha"
  } >"$run_dir/run.env"
  export PHASE1_JULIA PHASE1_GNU_TIME PHASE1_ACCOUNT PHASE1_QOS
  local raw job_id
  raw="$(sbatch --parsable \
    --account="$PHASE1_ACCOUNT" --constraint=cpu --qos="$PHASE1_QOS" \
    --nodes=1 --ntasks=1 --cpus-per-task="$PHASE1_SLURM_CPUS" \
    --mem="$PHASE1_MEMORY" --time="$PHASE1_TIME" --job-name=pb1-scan \
    --output="$run_dir/logs/scan-%j.out" --export=ALL \
    "$script_path" _run "$config_path" "$config_sha" "$run_dir" "$project_dir")"
  job_id="${raw%%;*}"
  printf 'job_id\tphase\tgeometry\tmps_period\ttwist_gauge\tbranch\tpreparation\tdirection\tseed_pattern\trandom_seed\tchi\tfluxes_over_pi\tslurm_cpus\tmemory\ttime_limit\tforecast_node_hours\tconfig_path\tconfig_sha256\trequire_parent_overlap\tminimum_parent_overlap_per_site\tparent_overlap_tolerance\tparent_overlap_krylov_dimension\tinitial_state_sha256\toptimizer_checkpoint_path\toptimizer_checkpoint_sha256\n' >"$run_dir/job.tsv"
  printf '%s\t1\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$job_id" "$geometry" "$period" "$gauge" "$branch" "$preparation" "$direction" \
    "$seed_pattern" "$random_seed" "$chi" "$fluxes" "$PHASE1_SLURM_CPUS" \
    "$PHASE1_MEMORY" "$PHASE1_TIME" "$forecast" "$config_path" "$config_sha" \
    "$require_overlap" "$minimum_overlap" "$overlap_tolerance" "$overlap_krylov" \
    "$initial_sha" "$optimizer_checkpoint" "$optimizer_checkpoint_sha" \
    >>"$run_dir/job.tsv"
  printf '%s\n' "$run_dir" >"$run_root/latest_run.txt"

  cat <<EOF
Submitted one Phase 1 pilot.
Job ID:                    $job_id
Run directory:             $run_dir
Worst-case reservation:    $forecast node-hours
Projected Phase 1 total:   $phase1_projected node-hours
Projected Project B total: $project_projected node-hours

After the job reaches a terminal state, reconcile it before another submit:
  bash "$script_path" reconcile "$run_id"
EOF
}

resolve_run_dir() {
  local requested="${1:-}"
  if [[ -n "$requested" && -d "$requested" ]]; then
    cd "$requested" && pwd
  elif [[ -n "$requested" && -d "$run_root/$requested" ]]; then
    cd "$run_root/$requested" && pwd
  elif [[ -z "$requested" && -d "$run_root" ]]; then
    # A directory sync can overwrite latest_run.txt with a stale pointer. Use
    # the greatest recorded Slurm job ID instead, without modifying either
    # the pointer or any immutable run record.
    local job_file candidate_id latest_id=-1 latest_dir=""
    while IFS= read -r job_file; do
      candidate_id="$(awk -F '\t' 'NR == 2 { print $1 }' "$job_file")"
      [[ "$candidate_id" =~ ^[0-9]+$ ]] || die "invalid job ID in $job_file"
      if (( candidate_id > latest_id )); then
        latest_id="$candidate_id"
        latest_dir="$(dirname "$job_file")"
      fi
    done < <(find "$run_root" -mindepth 2 -maxdepth 2 -name job.tsv -type f | sort)
    [[ -n "$latest_dir" ]] || die "no Phase 1 job records exist under $run_root"
    cd "$latest_dir" && pwd
  else
    die "cannot resolve Phase 1 run: ${requested:-latest}"
  fi
}

cancel_plateau_run() {
  [[ -n "${1:-}" ]] || die "cancel-plateau requires an explicit RUN_ID"
  require_command "$PHASE1_JULIA"
  require_command squeue
  require_command sacct
  local run_dir
  run_dir="$(resolve_run_dir "$1")"
  local job_file="$run_dir/job.tsv"
  local termination_path="$run_dir/termination.toml"
  [[ -f "$job_file" ]] || die "job record not found: $job_file"
  [[ ! -e "$termination_path" ]] || die \
    "scientific termination record already exists: $termination_path"
  local job_id
  job_id="$(awk -F '\t' 'NR == 2 { print $1 }' "$job_file")"
  [[ "$job_id" =~ ^[0-9]+$ ]] || die "invalid job ID in $job_file"

  local state action
  state="$(squeue -h -j "$job_id" -o '%T' 2>/dev/null |
    awk 'NF { print $1; exit }' || true)"
  if [[ "$state" == "RUNNING" || "$state" == "SUSPENDED" ]]; then
    require_command scancel
    scancel "$job_id"
    action="cancel_requested"
  elif [[ -n "$state" ]]; then
    die "job $job_id is $state, not RUNNING or SUSPENDED"
  else
    state="$(sacct -X -j "$job_id" --noheader --parsable2 \
      --format=JobIDRaw,State | awk -F '|' -v id="$job_id" '$1 == id { print $2; exit }')"
    [[ -n "$state" ]] || die "job $job_id is absent from both squeue and sacct"
    case "$state" in
      FAILED*|CANCELLED*|TIMEOUT*|OUT_OF_MEMORY*|NODE_FAIL*|PREEMPTED*|DEADLINE*|BOOT_FAIL*|REVOKED*)
        action="record_existing_terminal_failure"
        ;;
      *) die "job $job_id is terminal with state=$state; refusing to relabel it as a plateau" ;;
    esac
  fi

  local log_path="$run_dir/logs/scan-$job_id.out"
  [[ -f "$log_path" ]] || log_path=""
  "$PHASE1_JULIA" --startup-file=no -e '
    using Dates, TOML
    output_path, job_id, run_id, scheduler_state, action, log_path = ARGS
    text = isempty(log_path) ? "" : read(log_path, String)
    point_matches = collect(eachmatch(
      r"Point ([0-9]+):[^\n]*theta/pi=([^,\s]+)", text))
    iteration_matches = collect(eachmatch(
      r"VUMPS iteration ([0-9]+):[^\n]*residual=([^\s]+)", text))
    parse_or_nan(value) = try parse(Float64, value) catch; NaN end
    last_point = isempty(point_matches) ? nothing : last(point_matches)
    last_iteration = isempty(iteration_matches) ? nothing : last(iteration_matches)
    residuals = [parse_or_nan(match.captures[2]) for match in iteration_matches]
    finite_residuals = filter(isfinite, residuals)
    data = Dict{String,Any}(
      "schema_version" => 1,
      "artifact_kind" => "project_b_operator_termination",
      "created_at_utc" => string(now(UTC)),
      "job_id" => job_id,
      "run_id" => run_id,
      "scheduler_state_before_action" => scheduler_state,
      "scheduler_action" => action,
      "classification" => "operator_confirmed_numerical_plateau",
      "scientific_status" => "failed",
      "continuation_accepted" => false,
      "physical_endpoint" => false,
      "last_point_index" => isnothing(last_point) ? -1 : parse(Int, last_point.captures[1]),
      "last_theta_over_pi" => isnothing(last_point) ? NaN :
        parse_or_nan(last_point.captures[2]),
      "last_outer_iteration" => isnothing(last_iteration) ? -1 :
        parse(Int, last_iteration.captures[1]),
      "last_residual" => isnothing(last_iteration) ? NaN :
        parse_or_nan(last_iteration.captures[2]),
      "minimum_logged_residual" => isempty(finite_residuals) ? NaN :
        minimum(finite_residuals),
      "log_path" => log_path,
    )
    temporary_path = output_path * ".tmp"
    ispath(output_path) && error("refusing to overwrite $output_path")
    ispath(temporary_path) && error("stale temporary file exists: $temporary_path")
    open(temporary_path, "w") do io
      TOML.print(io, data; sorted=true)
    end
    Base.Filesystem.rename(temporary_path, output_path)
  ' "$termination_path" "$job_id" "$(basename "$run_dir")" "$state" "$action" "$log_path"

  cat <<EOF
Recorded an operator-confirmed numerical plateau for job $job_id.
Scheduler action:       $action
Scientific status:      failed (not a physical endpoint)
Termination artifact:   $termination_path

After the scheduler state becomes terminal, reconcile the actual charge:
  bash "$script_path" reconcile "$(basename "$run_dir")"
EOF
}

reconcile_run() {
  require_command sacct
  local run_dir
  run_dir="$(resolve_run_dir "${1:-}")"
  local job_file="$run_dir/job.tsv"
  [[ -f "$job_file" ]] || die "job record not found: $job_file"
  local job_id cpus memory
  job_id="$(awk -F '\t' 'NR == 2 { print $1 }' "$job_file")"
  cpus="$(awk -F '\t' 'NR == 2 { print $13 }' "$job_file")"
  memory="$(awk -F '\t' 'NR == 2 { print $14 }' "$job_file")"
  local allocation state elapsed
  allocation="$(sacct -X -j "$job_id" --noheader --parsable2 \
    --format=JobIDRaw,State,ElapsedRaw | awk -F '|' -v id="$job_id" '$1 == id { print $2 "|" $3; exit }')"
  [[ -n "$allocation" ]] || die "sacct has no allocation row for job $job_id"
  IFS='|' read -r state elapsed <<<"$allocation"
  case "$state" in
    COMPLETED*|FAILED*|CANCELLED*|TIMEOUT*|OUT_OF_MEMORY*|NODE_FAIL*|PREEMPTED*|DEADLINE*|BOOT_FAIL*|REVOKED*) ;;
    *) die "job $job_id is not terminal (state=$state)" ;;
  esac
  [[ "$elapsed" =~ ^[0-9]+$ ]] || die "invalid ElapsedRaw for job $job_id: $elapsed"
  local charge
  charge="$(node_hours_for_seconds "$cpus" "$memory" "$elapsed")"
  sacct -j "$job_id" --noheader --parsable2 \
    --format=JobIDRaw,JobName,State,ElapsedRaw,AllocCPUS,ReqMem,MaxRSS \
    >"$run_dir/sacct.tsv"
  printf '%s\n' "$charge" >"$run_dir/charged_node_hours.txt"
  cat <<EOF
Reconciled Phase 1 job $job_id.
State:              $state
Elapsed:            $elapsed seconds
Estimated charge:   $charge node-hours
Accounting export:  $run_dir/sacct.tsv
EOF
}

status_run() {
  local run_dir
  run_dir="$(resolve_run_dir "${1:-}")"
  local job_id
  job_id="$(awk -F '\t' 'NR == 2 { print $1 }' "$run_dir/job.tsv")"
  if command -v squeue >/dev/null 2>&1; then
    squeue -j "$job_id" -o '%.18i %.12j %.10T %.10M %.10l %.6D %R' 2>/dev/null || true
  fi
  if command -v sacct >/dev/null 2>&1; then
    sacct -X -j "$job_id" -o JobIDRaw,State,Elapsed,AllocCPUS,ReqMem || true
  fi
  [[ ! -f "$run_dir/job.result" ]] || cat "$run_dir/job.result"
  [[ ! -f "$run_dir/charged_node_hours.txt" ]] ||
    echo "Reconciled charge: $(cat "$run_dir/charged_node_hours.txt") node-hours"
}

submitted_jobs_for_config_sha() {
  local config_sha="$1"
  local matches=""
  local job_file job_id
  [[ -d "$run_root" ]] || {
    printf '\n'
    return
  }
  while IFS= read -r job_file; do
    job_id="$(awk -F '\t' -v expected="$config_sha" '
      NR == 1 {
        for (column_index = 1; column_index <= NF; column_index += 1) {
          if ($column_index == "config_sha256") config_column = column_index
        }
        next
      }
      NR == 2 && config_column > 0 && $config_column == expected { print $1 }
    ' "$job_file")"
    [[ -n "$job_id" ]] || continue
    matches="${matches}${matches:+,}${job_id}"
  done < <(find "$run_root" -mindepth 2 -maxdepth 2 -name job.tsv -type f | sort)
  printf '%s\n' "$matches"
}

automatic_advance_run() {
  local submit_next="$1"
  local requested="${2:-}"
  validate_project
  require_command "$PHASE1_JULIA"
  require_command sacct
  local run_dir
  run_dir="$(resolve_run_dir "$requested")"
  [[ -f "$run_dir/charged_node_hours.txt" ]] || reconcile_run "$run_dir"
  [[ -f "$run_dir/sacct.tsv" ]] || die \
    "automatic advance requires the reconciled accounting export $run_dir/sacct.tsv"

  local automation_script="$project_dir/scripts/prepare_phase1_automatic_advance.jl"
  [[ -f "$automation_script" ]] || die \
    "automatic Phase 1 advance script does not exist: $automation_script"
  local decision_path
  decision_path="$("$PHASE1_JULIA" --project="$project_dir" --startup-file=no \
    "$automation_script" "$run_dir")"
  [[ -f "$decision_path" ]] || die \
    "automatic Phase 1 advance did not produce a decision artifact: $decision_path"

  local record action transition reason submit_permitted next_config next_config_sha next_fluxes parent_theta
  record="$("$PHASE1_JULIA" --startup-file=no -e '
    using TOML
    decision = TOML.parsefile(ARGS[1])
    safe(value) = replace(String(value), '\''\t'\'' => '\'' '\'', '\''\n'\'' => '\'' '\'')
    println(join((
      safe(get(decision, "action", "")),
      safe(get(decision, "transition", "")),
      safe(get(decision, "reason", "")),
      string(get(decision, "submit_permitted", false)),
      safe(get(decision, "next_config_path", "")),
      safe(get(decision, "next_config_sha256", "")),
      join(get(decision, "next_fluxes_over_pi", Float64[]), ","),
      string(get(decision, "parent_theta_over_pi", NaN)),
    ), '\''\t'\''))
  ' "$decision_path")"
  IFS=$'\t' read -r action transition reason submit_permitted next_config next_config_sha next_fluxes parent_theta <<<"$record"

  cat <<EOF
Automatic Phase 1 decision:    $decision_path
Source run:                    $run_dir
Action:                        $action
Transition:                    ${transition:-none}
Reason:                        $reason
Accepted parent theta/pi:      $parent_theta
Next flux schedule:            ${next_fluxes:-none}
EOF

  case "$action" in
    complete)
      echo "The automated chi-512 campaign has reached theta/pi=1.0."
      return
      ;;
    manual_review)
      echo "No configuration was generated or submitted."
      return
      ;;
    next_config) ;;
    *) die "unknown automatic Phase 1 action '$action' in $decision_path" ;;
  esac
  [[ "$submit_permitted" == "true" ]] || die \
    "automatic decision generated a config but did not permit submission"
  [[ -f "$next_config" ]] || die "automatic next configuration is missing: $next_config"
  [[ "$(sha256_file "$next_config")" == "$next_config_sha" ]] || die \
    "automatic next configuration changed after decision creation: $next_config"

  print_plan "$next_config"
  if [[ "$submit_next" == "true" ]]; then
    local prior_jobs
    prior_jobs="$(submitted_jobs_for_config_sha "$next_config_sha")"
    [[ -z "$prior_jobs" ]] || die \
      "automatic configuration was already submitted as job(s) $prior_jobs; advance from the latest resulting run instead"
    submit_scan "$next_config"
  else
    cat <<EOF

The next transition is fully prepared but has not been submitted. To recheck
the immutable decision and submit through all live budget guards:
  bash "$script_path" advance-submit "$(basename "$run_dir")"
EOF
  fi
}

run_worker() {
  [[ "$#" -eq 4 ]] || die "internal _run usage: CONFIG SHA256 RUN_DIR PROJECT_DIR"
  local config_path="$1"
  local expected_sha="$2"
  local run_dir="$3"
  local submitted_project_dir="$4"
  [[ -n "${SLURM_JOB_ID:-}" ]] || die "_run is only valid inside a Slurm allocation"
  [[ "$submitted_project_dir" == /* ]] || die \
    "submitted project directory is not absolute: $submitted_project_dir"
  [[ -d "$submitted_project_dir" ]] || die \
    "submitted project directory does not exist: $submitted_project_dir"
  submitted_project_dir="$(cd "$submitted_project_dir" && pwd)"
  [[ -f "$submitted_project_dir/Project.toml" ]] || die \
    "Project.toml not found under submitted project directory $submitted_project_dir"
  [[ -f "$submitted_project_dir/scripts/run_scan.jl" ]] || die \
    "run_scan.jl not found under submitted project directory $submitted_project_dir"
  local effective_cpus="${SLURM_CPUS_PER_TASK:-}"
  validate_effective_cpu_allocation "$effective_cpus"
  [[ "$(sha256_file "$config_path")" == "$expected_sha" ]] || die \
    "configuration changed after submission; refusing to run"
  config_record "$config_path" >/dev/null
  require_command scontrol
  require_command "$PHASE1_GNU_TIME"
  local details
  details="$(scontrol show job "$SLURM_JOB_ID" -o)"
  [[ "$details" =~ QOS=shared([[:space:]]|$) ]] || die "worker allocation is not using QOS=shared"
  [[ "$details" =~ MinMemoryNode=([^[:space:]]+) ]] || die "cannot verify worker memory request"
  (( $(memory_to_mib "${BASH_REMATCH[1]}") >= 8192 )) || die "worker memory is below 8 GiB"

  mkdir -p "$run_dir/metrics"
  export JULIA_NUM_THREADS="$PHASE1_JULIA_THREADS"
  export OMP_NUM_THREADS=1
  export MKL_NUM_THREADS=1
  export OPENBLAS_NUM_THREADS=1
  {
    printf 'SLURM_JOB_ID=%q\n' "$SLURM_JOB_ID"
    printf 'SLURM_CPUS_PER_TASK=%q\n' "$SLURM_CPUS_PER_TASK"
    printf 'SCAN_STEP_CPUS=%q\n' "$PHASE1_SLURM_CPUS"
    printf 'JULIA_NUM_THREADS=%q\n' "$JULIA_NUM_THREADS"
    printf 'OMP_NUM_THREADS=%q\n' "$OMP_NUM_THREADS"
    printf 'MKL_NUM_THREADS=%q\n' "$MKL_NUM_THREADS"
    printf 'OPENBLAS_NUM_THREADS=%q\n' "$OPENBLAS_NUM_THREADS"
    printf 'CONFIG_SHA256=%q\n' "$expected_sha"
    printf 'PROJECT_DIR=%q\n' "$submitted_project_dir"
  } >"$run_dir/worker.env"

  local started finished exit_code
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  set +e
  "$PHASE1_GNU_TIME" -v -o "$run_dir/metrics/process.time" \
    srun --ntasks=1 --cpus-per-task="$PHASE1_SLURM_CPUS" --cpu-bind=cores \
    "$PHASE1_JULIA" --project="$submitted_project_dir" --startup-file=no \
    "$submitted_project_dir/scripts/run_scan.jl" "$config_path"
  exit_code=$?
  set -e
  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    printf 'job_id=%s\n' "$SLURM_JOB_ID"
    printf 'started_at_utc=%s\n' "$started"
    printf 'finished_at_utc=%s\n' "$finished"
    printf 'exit_code=%s\n' "$exit_code"
    printf 'config_path=%s\n' "$config_path"
    printf 'config_sha256=%s\n' "$expected_sha"
  } >"$run_dir/job.result"
  exit "$exit_code"
}

usage() {
  cat <<EOF
Usage:
  bash $(basename "$script_path") plan CONFIG.toml
  bash $(basename "$script_path") submit CONFIG.toml [RUN_ID]
  bash $(basename "$script_path") status [RUN_ID]
  bash $(basename "$script_path") cancel-plateau RUN_ID
  bash $(basename "$script_path") reconcile [RUN_ID]
  bash $(basename "$script_path") advance [RUN_ID]
  bash $(basename "$script_path") advance-submit [RUN_ID]

Direct `sbatch $(basename "$script_path") CONFIG.toml` is intentionally unsupported.
The submit command admits only the sparse, strict-lineage Phase 1 scout contract,
allows one Phase 1 pilot at a time, and refuses a new job until the prior pilot
has been reconciled with sacct.

The advance commands are restricted to the guarded YC8-1 chi-512 campaign.
They reconcile a terminal run, write an immutable decision, and either stop for
manual review or generate the next strict-lineage configuration. Only the
explicit advance-submit command may submit that generated configuration.
EOF
}

command_name="${1:-help}"
case "$command_name" in
  plan)
    [[ "$#" -eq 2 ]] || die "plan requires CONFIG.toml"
    print_plan "$2"
    ;;
  submit)
    [[ "$#" -eq 2 || "$#" -eq 3 ]] || die "submit requires CONFIG.toml [RUN_ID]"
    submit_scan "$2" "${3:-}"
    ;;
  status)
    [[ "$#" -le 2 ]] || die "status accepts at most one RUN_ID"
    status_run "${2:-}"
    ;;
  cancel-plateau)
    [[ "$#" -eq 2 ]] || die "cancel-plateau requires an explicit RUN_ID"
    cancel_plateau_run "$2"
    ;;
  reconcile)
    [[ "$#" -le 2 ]] || die "reconcile accepts at most one RUN_ID"
    reconcile_run "${2:-}"
    ;;
  advance)
    [[ "$#" -le 2 ]] || die "advance accepts at most one RUN_ID"
    automatic_advance_run false "${2:-}"
    ;;
  advance-submit)
    [[ "$#" -le 2 ]] || die "advance-submit accepts at most one RUN_ID"
    automatic_advance_run true "${2:-}"
    ;;
  _run)
    shift
    run_worker "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    die "unknown command: $command_name"
    ;;
esac
