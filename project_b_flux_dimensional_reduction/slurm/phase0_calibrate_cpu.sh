#!/bin/bash

# Phase 0 resource calibration for Project B on Perlmutter CPU nodes.
#
# This is intentionally a single-file workflow. It creates one deterministic
# YC6-1, chi=256 seed, reuses that exact state for every timing candidate, and
# compares mutually exclusive ITensor threading backends. The generated report
# ranks candidates by projected shared-QOS node-hours per VUMPS iteration.

set -euo pipefail

readonly PHASE0_SCRIPT_VERSION="1.1.1"
# NERSC shared CPU charging formula:
# https://docs.nersc.gov/jobs/examples/#perlmutter-cpu
readonly PERLMUTTER_MEMORY_MIB_PER_LOGICAL_CPU=1952
readonly PERLMUTTER_PHYSICAL_CORES_PER_CPU_NODE=128

PHASE0_ACCOUNT="${PHASE0_ACCOUNT:-m4863}"
PHASE0_QOS="${PHASE0_QOS:-shared}"
PHASE0_JULIA="${PHASE0_JULIA:-julia}"
PHASE0_PROJECT_BUDGET_NODE_HOURS="${PHASE0_PROJECT_BUDGET_NODE_HOURS:-150}"
PHASE0_MAX_NODE_HOURS="${PHASE0_MAX_NODE_HOURS:-10}"

PHASE0_SEED_CHI="${PHASE0_SEED_CHI:-256}"
PHASE0_VALIDATION_CHI="${PHASE0_VALIDATION_CHI:-512}"
PHASE0_SEED_THREADS="${PHASE0_SEED_THREADS:-8}"
PHASE0_SEED_MEMORY="${PHASE0_SEED_MEMORY:-96G}"
PHASE0_BENCH_MEMORY="${PHASE0_BENCH_MEMORY:-96G}"
PHASE0_SEED_TIME="${PHASE0_SEED_TIME:-06:00:00}"
PHASE0_BENCH_TIME="${PHASE0_BENCH_TIME:-02:00:00}"
PHASE0_VALIDATION_TIME="${PHASE0_VALIDATION_TIME:-04:00:00}"
PHASE0_REPORT_TIME="${PHASE0_REPORT_TIME:-00:15:00}"
PHASE0_WARMUP_ITERATIONS="${PHASE0_WARMUP_ITERATIONS:-1}"
PHASE0_BENCH_ITERATIONS="${PHASE0_BENCH_ITERATIONS:-3}"
PHASE0_MEMORY_SAFETY_PERCENT="${PHASE0_MEMORY_SAFETY_PERCENT:-30}"
PHASE0_VALIDATION_MEMORY_MAX_GIB="${PHASE0_VALIDATION_MEMORY_MAX_GIB:-240}"

initial_script_path="${BASH_SOURCE[0]}"
if [[ -n "${PHASE0_SCRIPT_PATH:-}" && -f "${PHASE0_SCRIPT_PATH}" ]]; then
  initial_script_path="${PHASE0_SCRIPT_PATH}"
fi
script_path="$(cd "$(dirname "$initial_script_path")" && pwd)/$(basename "$initial_script_path")"

if [[ -n "${PHASE0_PROJECT_DIR:-}" ]]; then
  project_dir="${PHASE0_PROJECT_DIR}"
elif [[ -n "${PROJECT_B_DIR:-}" ]]; then
  project_dir="${PROJECT_B_DIR}"
else
  project_dir="$(cd "$(dirname "$script_path")/.." && pwd)"
fi
project_dir="$(cd "$project_dir" && pwd)"
run_root="${PHASE0_RUN_ROOT:-$project_dir/output/phase0_calibration}"

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
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
  case "$raw" in
    *G)
      echo $(( ${raw%G} * 1024 ))
      ;;
    *M)
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
  echo $(( days * 86400 + 10#$first * 3600 + 10#$second * 60 + 10#$third ))
}

charged_physical_cores() {
  local logical_cpus="$1"
  local memory_mib="$2"
  local memory_logical
  memory_logical="$(ceil_div "$memory_mib" "$PERLMUTTER_MEMORY_MIB_PER_LOGICAL_CPU")"
  local unavailable="$logical_cpus"
  (( memory_logical > unavailable )) && unavailable="$memory_logical"
  ceil_div "$unavailable" 2
}

upper_bound_node_hours() {
  local logical_cpus="$1"
  local memory="$2"
  local time_limit="$3"
  local memory_mib seconds physical
  memory_mib="$(memory_to_mib "$memory")"
  seconds="$(time_to_seconds "$time_limit")"
  physical="$(charged_physical_cores "$logical_cpus" "$memory_mib")"
  awk -v seconds="$seconds" -v physical="$physical" \
    -v cores="$PERLMUTTER_PHYSICAL_CORES_PER_CPU_NODE" \
    'BEGIN { printf "%.9f", (seconds / 3600.0) * physical / cores }'
}

float_add() {
  awk -v left="$1" -v right="$2" 'BEGIN { printf "%.9f", left + right }'
}

candidate_rows() {
  # ITensor recommends benchmarking BLAS, Strided, and block-sparse threading
  # separately because enabling them together can cause thread competition:
  # https://docs.itensor.org/ITensors/stable/Multithreading.html
  # label               Julia threads   exclusive threading backend
  cat <<'EOF'
serial-t1	1	serial
serial-t8	8	serial
blocksparse-t2	2	blocksparse
blocksparse-t4	4	blocksparse
blocksparse-t8	8	blocksparse
blocksparse-t16	16	blocksparse
blocksparse-t32	32	blocksparse
strided-t4	4	strided
strided-t8	8	strided
strided-t16	16	strided
blas-t4	4	blas
blas-t8	8	blas
blas-t16	16	blas
EOF
}

phase0_upper_bound() {
  local total seed_cpus candidate logical contribution
  seed_cpus=$(( 2 * PHASE0_SEED_THREADS ))
  total="$(upper_bound_node_hours "$seed_cpus" "$PHASE0_SEED_MEMORY" "$PHASE0_SEED_TIME")"
  while IFS=$'\t' read -r candidate threads backend; do
    [[ -n "$candidate" ]] || continue
    logical=$(( 2 * threads ))
    contribution="$(upper_bound_node_hours "$logical" "$PHASE0_BENCH_MEMORY" "$PHASE0_BENCH_TIME")"
    total="$(float_add "$total" "$contribution")"
  done < <(candidate_rows)

  # Include the optional chi=512 validation at the largest allowed shared-memory footprint.
  contribution="$(upper_bound_node_hours 64 "${PHASE0_VALIDATION_MEMORY_MAX_GIB}G" "$PHASE0_VALIDATION_TIME")"
  total="$(float_add "$total" "$contribution")"
  contribution="$(upper_bound_node_hours 2 2G "$PHASE0_REPORT_TIME")"
  total="$(float_add "$total" "$contribution")"
  # The optional validation schedules a second automatic report.
  total="$(float_add "$total" "$contribution")"
  echo "$total"
}

validate_local_project() {
  [[ -f "$project_dir/Project.toml" ]] || die "Project.toml not found under $project_dir"
  [[ -f "$project_dir/src/TriangularJ1J2ProjectB.jl" ]] || \
    die "Project B source not found under $project_dir"
  [[ -f "$script_path" ]] || die "script path is not readable: $script_path"
  [[ "$PHASE0_QOS" == "shared" ]] || die "Phase 0 requires the shared QOS"
  [[ "$PHASE0_ACCOUNT" =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid NERSC account: $PHASE0_ACCOUNT"
  [[ "$PHASE0_SEED_CHI" =~ ^[0-9]+$ ]] || die "PHASE0_SEED_CHI must be an integer"
  [[ "$PHASE0_VALIDATION_CHI" =~ ^[0-9]+$ ]] || die "PHASE0_VALIDATION_CHI must be an integer"
  (( PHASE0_VALIDATION_CHI > PHASE0_SEED_CHI )) || \
    die "validation chi must exceed seed chi"
  (( PHASE0_WARMUP_ITERATIONS >= 1 )) || die "at least one warm-up iteration is required"
  (( PHASE0_BENCH_ITERATIONS >= 2 )) || die "at least two measured iterations are required"
}

print_plan() {
  validate_local_project
  local candidate_count bound
  candidate_count="$(candidate_rows | awk 'NF { count += 1 } END { print count + 0 }')"
  bound="$(phase0_upper_bound)"
  cat <<EOF
Project B hard budget:          ${PHASE0_PROJECT_BUDGET_NODE_HOURS} node-hours
Phase 0 enforced ceiling:       ${PHASE0_MAX_NODE_HOURS} node-hours
Worst-case Phase 0 reservation: ${bound} node-hours

Seed: YC6-1, theta=0, chi=${PHASE0_SEED_CHI}, 2-site Hu cell, uniform gauge, ${PHASE0_SEED_THREADS} Julia threads
Matrix: ${candidate_count} jobs, ${PHASE0_WARMUP_ITERATIONS} warm-up + ${PHASE0_BENCH_ITERATIONS} measured iterations each
Backends: serial, block-sparse, Strided, and BLAS (never enabled together)
Optional validation: one chi=${PHASE0_VALIDATION_CHI} expansion and VUMPS iteration
EOF
  if awk -v bound="$bound" -v cap="$PHASE0_MAX_NODE_HOURS" 'BEGIN { exit !(bound > cap) }'; then
    die "configured worst-case Phase 0 reservation exceeds its ceiling"
  fi
}

write_run_environment() {
  local path="$1"
  {
    printf 'PHASE0_RUN_SCRIPT_VERSION=%q\n' "$PHASE0_SCRIPT_VERSION"
    printf 'PHASE0_SCRIPT_PATH=%q\n' "$script_path"
    printf 'PHASE0_PROJECT_DIR=%q\n' "$project_dir"
    printf 'PHASE0_ACCOUNT=%q\n' "$PHASE0_ACCOUNT"
    printf 'PHASE0_QOS=%q\n' "$PHASE0_QOS"
    printf 'PHASE0_JULIA=%q\n' "$PHASE0_JULIA"
    printf 'PHASE0_PROJECT_BUDGET_NODE_HOURS=%q\n' "$PHASE0_PROJECT_BUDGET_NODE_HOURS"
    printf 'PHASE0_MAX_NODE_HOURS=%q\n' "$PHASE0_MAX_NODE_HOURS"
    printf 'PHASE0_SEED_CHI=%q\n' "$PHASE0_SEED_CHI"
    printf 'PHASE0_VALIDATION_CHI=%q\n' "$PHASE0_VALIDATION_CHI"
    printf 'PHASE0_SEED_THREADS=%q\n' "$PHASE0_SEED_THREADS"
    printf 'PHASE0_SEED_MEMORY=%q\n' "$PHASE0_SEED_MEMORY"
    printf 'PHASE0_BENCH_MEMORY=%q\n' "$PHASE0_BENCH_MEMORY"
    printf 'PHASE0_SEED_TIME=%q\n' "$PHASE0_SEED_TIME"
    printf 'PHASE0_BENCH_TIME=%q\n' "$PHASE0_BENCH_TIME"
    printf 'PHASE0_VALIDATION_TIME=%q\n' "$PHASE0_VALIDATION_TIME"
    printf 'PHASE0_REPORT_TIME=%q\n' "$PHASE0_REPORT_TIME"
    printf 'PHASE0_WARMUP_ITERATIONS=%q\n' "$PHASE0_WARMUP_ITERATIONS"
    printf 'PHASE0_BENCH_ITERATIONS=%q\n' "$PHASE0_BENCH_ITERATIONS"
    printf 'PHASE0_MEMORY_SAFETY_PERCENT=%q\n' "$PHASE0_MEMORY_SAFETY_PERCENT"
    printf 'PHASE0_VALIDATION_MEMORY_MAX_GIB=%q\n' "$PHASE0_VALIDATION_MEMORY_MAX_GIB"
  } >"$path"
}

submit_phase0() {
  validate_local_project
  require_command sbatch
  local bound
  bound="$(phase0_upper_bound)"
  if awk -v bound="$bound" -v cap="$PHASE0_MAX_NODE_HOURS" 'BEGIN { exit !(bound > cap) }'; then
    die "refusing submission: worst-case ${bound} node-hours exceeds Phase 0 cap ${PHASE0_MAX_NODE_HOURS}"
  fi

  local run_id="${1:-$(date -u +%Y%m%dT%H%M%SZ)}"
  [[ "$run_id" =~ ^[A-Za-z0-9_.-]+$ ]] || die "run id contains unsafe characters: $run_id"
  local run_dir="$run_root/$run_id"
  [[ ! -e "$run_dir" ]] || die "run directory already exists: $run_dir"
  mkdir -p "$run_dir/logs" "$run_dir/metrics"
  write_run_environment "$run_dir/run.env"
  printf '%s\n' "$bound" >"$run_dir/worst_case_node_hours.txt"

  {
    printf 'label\tjulia_threads\tbackend\n'
    candidate_rows
  } >"$run_dir/candidates.tsv"
  printf 'kind\tlabel\tbackend\tjulia_threads\tslurm_logical_cpus\tmemory\tjob_id\n' \
    >"$run_dir/jobs.tsv"

  export PHASE0_SCRIPT_PATH="$script_path"
  export PHASE0_PROJECT_DIR="$project_dir"
  export PHASE0_JULIA

  local seed_cpus seed_raw seed_id
  seed_cpus=$(( 2 * PHASE0_SEED_THREADS ))
  seed_raw="$(sbatch --parsable \
    --account="$PHASE0_ACCOUNT" --constraint=cpu --qos="$PHASE0_QOS" \
    --nodes=1 --ntasks=1 --cpus-per-task="$seed_cpus" --mem="$PHASE0_SEED_MEMORY" \
    --time="$PHASE0_SEED_TIME" --job-name=pb0-seed \
    --output="$run_dir/logs/seed-%j.out" --export=ALL \
    "$script_path" _seed "$run_dir")"
  seed_id="${seed_raw%%;*}"
  printf 'seed\tseed\tblocksparse\t%s\t%s\t%s\t%s\n' \
    "$PHASE0_SEED_THREADS" "$seed_cpus" "$PHASE0_SEED_MEMORY" "$seed_id" \
    >>"$run_dir/jobs.tsv"

  local -a benchmark_ids=()
  local label threads backend logical raw job_id
  while IFS=$'\t' read -r label threads backend; do
    [[ -n "$label" ]] || continue
    logical=$(( 2 * threads ))
    raw="$(sbatch --parsable \
      --account="$PHASE0_ACCOUNT" --constraint=cpu --qos="$PHASE0_QOS" \
      --nodes=1 --ntasks=1 --cpus-per-task="$logical" --mem="$PHASE0_BENCH_MEMORY" \
      --time="$PHASE0_BENCH_TIME" --job-name="pb0-$label" \
      --dependency="afterany:$seed_id" --kill-on-invalid-dep=yes \
      --output="$run_dir/logs/${label}-%j.out" --export=ALL \
      "$script_path" _bench "$run_dir" "$label" "$threads" "$backend")"
    job_id="${raw%%;*}"
    benchmark_ids+=("$job_id")
    printf 'benchmark\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$label" "$backend" "$threads" "$logical" "$PHASE0_BENCH_MEMORY" "$job_id" \
      >>"$run_dir/jobs.tsv"
  done < <(candidate_rows)

  local dependency report_raw report_id
  dependency="$(IFS=:; echo "${benchmark_ids[*]}")"
  report_raw="$(sbatch --parsable \
    --account="$PHASE0_ACCOUNT" --constraint=cpu --qos="$PHASE0_QOS" \
    --nodes=1 --ntasks=1 --cpus-per-task=2 --mem=2G \
    --time="$PHASE0_REPORT_TIME" --job-name=pb0-report \
    --dependency="afterany:$dependency" --kill-on-invalid-dep=yes \
    --output="$run_dir/logs/report-%j.out" --export=ALL \
    "$script_path" _report "$run_dir")"
  report_id="${report_raw%%;*}"
  printf 'report\treport\tserial\t1\t2\t2G\t%s\n' "$report_id" >>"$run_dir/jobs.tsv"

  mkdir -p "$run_root"
  printf '%s\n' "$run_dir" >"$run_root/latest_run.txt"

  cat <<EOF
Submitted Phase 0 calibration: $run_id
Seed job:                      $seed_id
Benchmark jobs:                ${benchmark_ids[*]}
Automatic report job:          $report_id
Worst-case reservation:        $bound node-hours (cap $PHASE0_MAX_NODE_HOURS)
Run directory:                 $run_dir

Monitor:
  bash "$script_path" status "$run_id"

After the report completes:
  bash "$script_path" show "$run_id"

Then validate the winner once at chi=$PHASE0_VALIDATION_CHI:
  bash "$script_path" validate "$run_id"
EOF
}

resolve_run_dir() {
  local requested="${1:-}"
  if [[ -n "$requested" && -d "$requested" ]]; then
    cd "$requested" && pwd
    return
  fi
  if [[ -n "$requested" && -d "$run_root/$requested" ]]; then
    cd "$run_root/$requested" && pwd
    return
  fi
  if [[ -z "$requested" && -f "$run_root/latest_run.txt" ]]; then
    local latest
    latest="$(<"$run_root/latest_run.txt")"
    [[ -d "$latest" ]] || die "latest run directory no longer exists: $latest"
    cd "$latest" && pwd
    return
  fi
  die "cannot resolve Phase 0 run: ${requested:-latest}"
}

load_run_environment() {
  local run_dir="$1"
  [[ -f "$run_dir/run.env" ]] || die "missing run environment: $run_dir/run.env"
  # This file is generated by this script using shell-escaped values.
  # shellcheck disable=SC1090
  source "$run_dir/run.env"
  script_path="$PHASE0_SCRIPT_PATH"
  project_dir="$PHASE0_PROJECT_DIR"
}

set_thread_environment() {
  local threads="$1"
  local backend="$2"
  export JULIA_NUM_THREADS="$threads"
  export JULIA_PKG_PRECOMPILE_AUTO=0
  export OMP_PROC_BIND=spread
  export OMP_PLACES=threads
  if [[ "$backend" == "blas" ]]; then
    export OMP_NUM_THREADS="$threads"
    export MKL_NUM_THREADS="$threads"
    export OPENBLAS_NUM_THREADS="$threads"
  else
    export OMP_NUM_THREADS=1
    export MKL_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1
  fi
}

readonly JULIA_PAYLOAD_LOADER='source = read(ENV["PHASE0_SCRIPT_PATH"], String); begin_token = "#= BEGIN_" * "PHASE0_JULIA_PAYLOAD =#"; end_token = "#= END_" * "PHASE0_JULIA_PAYLOAD =#"; first_split = split(source, begin_token; limit=2); length(first_split) == 2 || error("Julia payload start marker missing"); second_split = split(first_split[2], end_token; limit=2); length(second_split) == 2 || error("Julia payload end marker missing"); Base.include_string(Main, second_split[1], ENV["PHASE0_SCRIPT_PATH"] * ":payload")'

run_timed_julia_payload() {
  local time_file="$1"
  local threads="$2"
  shift 2
  local logical="${SLURM_CPUS_PER_TASK:-$(( 2 * threads ))}"
  require_command srun
  require_command /usr/bin/time
  command -v "$PHASE0_JULIA" >/dev/null 2>&1 || \
    die "Julia executable not found: $PHASE0_JULIA (set PHASE0_JULIA to an absolute path)"
  srun --ntasks=1 --cpus-per-task="$logical" --cpu-bind=cores \
    /usr/bin/time -v -o "$time_file" \
    "$PHASE0_JULIA" --threads="$threads" --project="$project_dir" --startup-file=no \
    -e "$JULIA_PAYLOAD_LOADER" -- "$@"
}

run_seed_worker() {
  local run_dir="$1"
  load_run_environment "$run_dir"
  [[ -n "${SLURM_JOB_ID:-}" ]] || die "_seed must run inside a Slurm allocation"
  set_thread_environment "$PHASE0_SEED_THREADS" blocksparse
  run_timed_julia_payload "$run_dir/metrics/seed.time" "$PHASE0_SEED_THREADS" \
    seed "$run_dir" "$PHASE0_SEED_CHI"
}

run_benchmark_worker() {
  local run_dir="$1"
  local label="$2"
  local threads="$3"
  local backend="$4"
  load_run_environment "$run_dir"
  [[ -n "${SLURM_JOB_ID:-}" ]] || die "_bench must run inside a Slurm allocation"
  [[ -f "$run_dir/seed_state.h5" ]] || die "seed job failed or produced no state"
  set_thread_environment "$threads" "$backend"
  run_timed_julia_payload "$run_dir/metrics/${label}.time" "$threads" \
    benchmark "$run_dir" "$label" "$threads" "$backend" \
    "$PHASE0_WARMUP_ITERATIONS" "$PHASE0_BENCH_ITERATIONS"
}

kv_value() {
  local path="$1"
  local key="$2"
  awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print; exit }' "$path"
}

max_rss_kib() {
  local path="$1"
  awk -F: '/Maximum resident set size \(kbytes\)/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$path"
}

sacct_allocation_row() {
  local job_id="$1"
  if ! command -v sacct >/dev/null 2>&1; then
    echo 'UNKNOWN|0|0'
    return
  fi
  local row=''
  local attempt
  for attempt in 1 2 3 4 5; do
    row="$(sacct -X -j "$job_id" --noheader --parsable2 \
      --format=State,ElapsedRaw,AllocCPUS 2>/dev/null | awk 'NF { print; exit }' || true)"
    [[ -n "$row" ]] && break
    sleep 2
  done
  [[ -n "$row" ]] && echo "$row" || echo 'UNKNOWN|0|0'
}

recommended_memory_mib() {
  local rss_kib="$1"
  local rss_mib padded rounded
  rss_mib="$(ceil_div "$rss_kib" 1024)"
  padded="$(ceil_div $(( rss_mib * (100 + PHASE0_MEMORY_SAFETY_PERCENT) )) 100)"
  rounded=$(( $(ceil_div "$padded" 2048) * 2048 ))
  (( rounded < 8192 )) && rounded=8192
  echo "$rounded"
}

generate_report() {
  local run_dir="$1"
  load_run_environment "$run_dir"
  local summary_tmp="$run_dir/summary.csv.tmp"
  local summary="$run_dir/summary.csv"
  printf '%s\n' \
    'label,backend,julia_threads,slurm_logical_cpus,job_id,state,iterations,kernel_seconds,seconds_per_iteration,max_rss_gib,recommended_mem_gib,projected_physical_cores,projected_node_hours_per_iteration,elapsed_seconds,estimated_actual_node_hours' \
    >"$summary_tmp"

  local best_label='' best_backend='' best_threads='' best_logical=''
  local best_mem_gib='' best_cost='' candidate_charge_total=0
  local label threads backend kind ignored job_memory job_id
  while IFS=$'\t' read -r label threads backend; do
    [[ "$label" == "label" || -z "$label" ]] && continue
    local job_row
    job_row="$(awk -F'\t' -v wanted="$label" '$1 == "benchmark" && $2 == wanted { print; exit }' "$run_dir/jobs.tsv")"
    [[ -n "$job_row" ]] || continue
    IFS=$'\t' read -r kind ignored ignored threads logical job_memory job_id <<<"$job_row"

    local state elapsed alloc extra
    IFS='|' read -r state elapsed alloc extra <<<"$(sacct_allocation_row "$job_id")"
    state="${state:-UNKNOWN}"
    elapsed="${elapsed:-0}"
    alloc="${alloc:-0}"
    [[ "$elapsed" =~ ^[0-9]+$ ]] || elapsed=0
    [[ "$alloc" =~ ^[0-9]+$ ]] || alloc="$logical"
    (( alloc > 0 )) || alloc="$logical"

    local result_file="$run_dir/metrics/${label}.result"
    local time_file="$run_dir/metrics/${label}.time"
    if [[ ! -f "$result_file" || ! -f "$time_file" ]]; then
      printf '%s,%s,%s,%s,%s,%s,0,nan,nan,nan,nan,nan,nan,%s,nan\n' \
        "$label" "$backend" "$threads" "$logical" "$job_id" "$state" "$elapsed" \
        >>"$summary_tmp"
      continue
    fi

    local iterations kernel_seconds rss_kib rss_mib rss_gib rec_mib rec_gib
    local seconds_per_iter projected_physical projected_cost requested_mib actual_physical actual_charge
    iterations="$(kv_value "$result_file" iterations)"
    kernel_seconds="$(kv_value "$result_file" kernel_seconds)"
    rss_kib="$(max_rss_kib "$time_file")"
    [[ "$iterations" =~ ^[0-9]+$ ]] || iterations=0
    [[ "$rss_kib" =~ ^[0-9]+$ ]] || rss_kib=0
    if (( iterations == 0 || rss_kib == 0 )); then
      printf '%s,%s,%s,%s,%s,%s,%s,%s,nan,nan,nan,nan,nan,%s,nan\n' \
        "$label" "$backend" "$threads" "$logical" "$job_id" "$state" \
        "$iterations" "$kernel_seconds" "$elapsed" >>"$summary_tmp"
      continue
    fi

    rss_mib="$(ceil_div "$rss_kib" 1024)"
    rss_gib="$(awk -v mib="$rss_mib" 'BEGIN { printf "%.3f", mib / 1024.0 }')"
    rec_mib="$(recommended_memory_mib "$rss_kib")"
    rec_gib="$(ceil_div "$rec_mib" 1024)"
    seconds_per_iter="$(awk -v seconds="$kernel_seconds" -v iterations="$iterations" \
      'BEGIN { printf "%.6f", seconds / iterations }')"
    projected_physical="$(charged_physical_cores "$logical" "$rec_mib")"
    projected_cost="$(awk -v seconds="$seconds_per_iter" -v physical="$projected_physical" \
      -v cores="$PERLMUTTER_PHYSICAL_CORES_PER_CPU_NODE" \
      'BEGIN { printf "%.9f", (seconds / 3600.0) * physical / cores }')"

    requested_mib="$(memory_to_mib "$job_memory")"
    actual_physical="$(charged_physical_cores "$alloc" "$requested_mib")"
    actual_charge="$(awk -v seconds="$elapsed" -v physical="$actual_physical" \
      -v cores="$PERLMUTTER_PHYSICAL_CORES_PER_CPU_NODE" \
      'BEGIN { printf "%.6f", (seconds / 3600.0) * physical / cores }')"
    candidate_charge_total="$(float_add "$candidate_charge_total" "$actual_charge")"

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$label" "$backend" "$threads" "$logical" "$job_id" "$state" "$iterations" \
      "$kernel_seconds" "$seconds_per_iter" "$rss_gib" "$rec_gib" \
      "$projected_physical" "$projected_cost" "$elapsed" "$actual_charge" \
      >>"$summary_tmp"

    if [[ "$state" == COMPLETED* ]]; then
      if [[ -z "$best_cost" ]] || \
         awk -v candidate="$projected_cost" -v best="$best_cost" \
           'BEGIN { exit !(candidate < best) }'; then
        best_label="$label"
        best_backend="$backend"
        best_threads="$threads"
        best_logical="$logical"
        best_mem_gib="$rec_gib"
        best_cost="$projected_cost"
      fi
    fi
  done <"$run_dir/candidates.tsv"
  mv "$summary_tmp" "$summary"

  local seed_job_id seed_state seed_elapsed seed_alloc seed_extra seed_rss_kib=0 seed_rss_gib=nan
  local seed_result seed_mps_period='unknown' seed_minimal_period='2' seed_cell_status='unknown'
  local seed_requested_mib seed_physical seed_charge=0 validation_charge=0 total_charge
  seed_job_id="$(awk -F'\t' '$1 == "seed" { print $7; exit }' "$run_dir/jobs.tsv")"
  seed_result="$run_dir/metrics/seed.result"
  if [[ -f "$seed_result" ]]; then
    seed_mps_period="$(kv_value "$seed_result" mps_period)"
    seed_minimal_period="$(kv_value "$seed_result" minimal_mps_period)"
    seed_cell_status="$(kv_value "$seed_result" unit_cell_status)"
  fi
  IFS='|' read -r seed_state seed_elapsed seed_alloc seed_extra \
    <<<"$(sacct_allocation_row "$seed_job_id")"
  [[ "$seed_elapsed" =~ ^[0-9]+$ ]] || seed_elapsed=0
  [[ "$seed_alloc" =~ ^[0-9]+$ ]] || seed_alloc=$(( 2 * PHASE0_SEED_THREADS ))
  if [[ -f "$run_dir/metrics/seed.time" ]]; then
    seed_rss_kib="$(max_rss_kib "$run_dir/metrics/seed.time")"
    [[ "$seed_rss_kib" =~ ^[0-9]+$ ]] || seed_rss_kib=0
  fi
  if (( seed_rss_kib > 0 )); then
    seed_rss_gib="$(awk -v kib="$seed_rss_kib" 'BEGIN { printf "%.3f", kib / 1048576.0 }')"
  fi
  seed_requested_mib="$(memory_to_mib "$PHASE0_SEED_MEMORY")"
  seed_physical="$(charged_physical_cores "$seed_alloc" "$seed_requested_mib")"
  seed_charge="$(awk -v seconds="$seed_elapsed" -v physical="$seed_physical" \
    -v cores="$PERLMUTTER_PHYSICAL_CORES_PER_CPU_NODE" \
    'BEGIN { printf "%.6f", (seconds / 3600.0) * physical / cores }')"

  local validation_job_row validation_job_id validation_memory validation_state
  local validation_elapsed validation_alloc validation_extra validation_mib validation_physical
  validation_job_row="$(awk -F'\t' '$1 == "validation" { print; exit }' "$run_dir/jobs.tsv")"
  if [[ -n "$validation_job_row" ]]; then
    IFS=$'\t' read -r kind ignored backend threads logical validation_memory validation_job_id \
      <<<"$validation_job_row"
    IFS='|' read -r validation_state validation_elapsed validation_alloc validation_extra \
      <<<"$(sacct_allocation_row "$validation_job_id")"
    [[ "$validation_elapsed" =~ ^[0-9]+$ ]] || validation_elapsed=0
    [[ "$validation_alloc" =~ ^[0-9]+$ ]] || validation_alloc="$logical"
    validation_mib="$(memory_to_mib "$validation_memory")"
    validation_physical="$(charged_physical_cores "$validation_alloc" "$validation_mib")"
    validation_charge="$(awk -v seconds="$validation_elapsed" -v physical="$validation_physical" \
      -v cores="$PERLMUTTER_PHYSICAL_CORES_PER_CPU_NODE" \
      'BEGIN { printf "%.6f", (seconds / 3600.0) * physical / cores }')"
  fi
  total_charge="$(float_add "$candidate_charge_total" "$seed_charge")"
  total_charge="$(float_add "$total_charge" "$validation_charge")"

  local recommendation_env="$run_dir/recommendation.env"
  local recommendation_txt="$run_dir/recommendation.txt"
  if [[ -z "$best_label" ]]; then
    rm -f "$recommendation_env"
    cat >"$recommendation_txt" <<EOF
Phase 0 did not produce a valid recommendation.

Seed state:             $seed_state
Seed MaxRSS:            $seed_rss_gib GiB
Estimated seed charge:  $seed_charge node-hours
Estimated matrix charge: $candidate_charge_total node-hours

Inspect $summary and the logs under $run_dir/logs.
EOF
    cat "$recommendation_txt"
    return 1
  fi

  {
    printf 'PHASE0_RECOMMENDED_LABEL=%q\n' "$best_label"
    printf 'PHASE0_RECOMMENDED_BACKEND=%q\n' "$best_backend"
    printf 'PHASE0_RECOMMENDED_JULIA_THREADS=%q\n' "$best_threads"
    printf 'PHASE0_RECOMMENDED_SLURM_CPUS=%q\n' "$best_logical"
    printf 'PHASE0_RECOMMENDED_MEMORY_GIB=%q\n' "$best_mem_gib"
    printf 'PHASE0_PROJECTED_NODE_HOURS_PER_ITERATION=%q\n' "$best_cost"
    printf 'PHASE0_MPS_PERIOD=%q\n' "$seed_mps_period"
    printf 'PHASE0_MINIMAL_MPS_PERIOD=%q\n' "$seed_minimal_period"
    printf 'PHASE0_UNIT_CELL_STATUS=%q\n' "$seed_cell_status"
  } >"$recommendation_env"

  local validation_line='not run'
  local validation_memory_line='not available'
  local validation_cost_line='not available'
  local validation_guidance="It is a chi=$PHASE0_SEED_CHI result; run the one-point chi=$PHASE0_VALIDATION_CHI validation before production."
  local validation_result="$run_dir/metrics/validation.result"
  local validation_time_file="$run_dir/metrics/validation.time"
  if [[ -f "$validation_result" && -f "$validation_time_file" ]]; then
    local validation_seconds validation_rss validation_rec_mib validation_rec_gib
    local validation_projected_physical validation_projected_cost
    validation_seconds="$(kv_value "$validation_result" kernel_seconds)"
    validation_rss="$(max_rss_kib "$validation_time_file")"
    if [[ "$validation_rss" =~ ^[0-9]+$ ]]; then
      validation_line="chi=$PHASE0_VALIDATION_CHI iteration ${validation_seconds}s, MaxRSS $(awk -v kib="$validation_rss" 'BEGIN { printf "%.3f GiB", kib / 1048576.0 }')"
      validation_rec_mib="$(recommended_memory_mib "$validation_rss")"
      validation_rec_gib="$(ceil_div "$validation_rec_mib" 1024)"
      validation_projected_physical="$(charged_physical_cores "$best_logical" "$validation_rec_mib")"
      validation_projected_cost="$(awk -v seconds="$validation_seconds" \
        -v physical="$validation_projected_physical" \
        -v cores="$PERLMUTTER_PHYSICAL_CORES_PER_CPU_NODE" \
        'BEGIN { printf "%.9f", (seconds / 3600.0) * physical / cores }')"
      validation_memory_line="${validation_rec_gib}G"
      validation_cost_line="$validation_projected_cost node-hours/iteration"
      validation_guidance="The chi=$PHASE0_VALIDATION_CHI validation completed; use its measured memory request for jobs at that scale."
      {
        printf 'PHASE0_VALIDATED_CHI=%q\n' "$PHASE0_VALIDATION_CHI"
        printf 'PHASE0_VALIDATED_MEMORY_GIB=%q\n' "$validation_rec_gib"
        printf 'PHASE0_VALIDATED_NODE_HOURS_PER_ITERATION=%q\n' "$validation_projected_cost"
      } >>"$recommendation_env"
    fi
  fi

  cat >"$recommendation_txt" <<EOF
Phase 0 recommendation
======================

Winner:                         $best_label
Exclusive threading backend:   $best_backend
Julia/compute threads:          $best_threads
Slurm --cpus-per-task:          $best_logical logical CPUs
Right-sized memory request:     ${best_mem_gib}G
Projected node-hours/iteration: $best_cost
MPS period / required period:   $seed_mps_period / $seed_minimal_period ($seed_cell_status)

Seed MaxRSS:                    $seed_rss_gib GiB
Estimated seed charge:          $seed_charge node-hours
Estimated benchmark charge:     $candidate_charge_total node-hours
Estimated validation charge:    $validation_charge node-hours
Estimated Phase 0 charge so far: $total_charge node-hours
Chi=$PHASE0_VALIDATION_CHI validation:          $validation_line
Validated chi=$PHASE0_VALIDATION_CHI memory:    $validation_memory_line
Validated chi=$PHASE0_VALIDATION_CHI cost:      $validation_cost_line

The ranking uses a ${PHASE0_MEMORY_SAFETY_PERCENT}% MaxRSS margin, rounds memory upward to 2 GiB,
and applies Perlmutter shared-QOS charging to the measured VUMPS kernel time.
$validation_guidance

$(if [[ "$seed_cell_status" != "minimal" ]]; then
    echo "WARNING: this run used a legacy YC6-1 supercell. Preserve the timing, but rerun Phase 0 with the corrected two-site seed before production."
  fi)

Candidate details: $summary
EOF
  cat "$recommendation_txt"
}

status_phase0() {
  local run_dir
  run_dir="$(resolve_run_dir "${1:-}")"
  printf 'Run: %s\n\n' "$run_dir"
  printf '%-12s %-20s %-12s %-12s\n' KIND LABEL JOB_ID STATE
  local kind label backend threads logical memory job_id state
  while IFS=$'\t' read -r kind label backend threads logical memory job_id; do
    [[ "$kind" == "kind" || -z "$kind" ]] && continue
    state='UNKNOWN'
    if command -v squeue >/dev/null 2>&1; then
      state="$(squeue --noheader --jobs="$job_id" --format='%T' 2>/dev/null | awk 'NF { print; exit }' || true)"
    fi
    if [[ -z "$state" ]] && command -v sacct >/dev/null 2>&1; then
      state="$(sacct -X -j "$job_id" --noheader --parsable2 --format=State 2>/dev/null \
        | awk -F'|' 'NF { print $1; exit }' || true)"
    fi
    printf '%-12s %-20s %-12s %-12s\n' "$kind" "$label" "$job_id" "${state:-UNKNOWN}"
  done <"$run_dir/jobs.tsv"
}

show_phase0() {
  local run_dir
  run_dir="$(resolve_run_dir "${1:-}")"
  if [[ -f "$run_dir/recommendation.txt" ]]; then
    cat "$run_dir/recommendation.txt"
  else
    echo "No report yet. Current status:"
    status_phase0 "$run_dir"
    return 1
  fi
}

manual_report_phase0() {
  local run_dir
  run_dir="$(resolve_run_dir "${1:-}")"
  generate_report "$run_dir"
}

submit_validation() {
  require_command sbatch
  local run_dir
  run_dir="$(resolve_run_dir "${1:-}")"
  load_run_environment "$run_dir"
  [[ -f "$run_dir/recommendation.env" ]] || \
    die "no recommendation is available; wait for the report job or run 'report'"
  if awk -F'\t' '$1 == "validation" { found=1 } END { exit !found }' "$run_dir/jobs.tsv"; then
    die "a validation job has already been submitted for this run"
  fi
  # shellcheck disable=SC1090
  source "$run_dir/recommendation.env"

  local validation_memory_gib=$(( PHASE0_RECOMMENDED_MEMORY_GIB * 4 ))
  (( validation_memory_gib < 64 )) && validation_memory_gib=64
  (( validation_memory_gib > PHASE0_VALIDATION_MEMORY_MAX_GIB )) && \
    validation_memory_gib="$PHASE0_VALIDATION_MEMORY_MAX_GIB"

  export PHASE0_SCRIPT_PATH="$script_path"
  export PHASE0_PROJECT_DIR="$project_dir"
  export PHASE0_JULIA
  local raw job_id
  raw="$(sbatch --parsable \
    --account="$PHASE0_ACCOUNT" --constraint=cpu --qos="$PHASE0_QOS" \
    --nodes=1 --ntasks=1 --cpus-per-task="$PHASE0_RECOMMENDED_SLURM_CPUS" \
    --mem="${validation_memory_gib}G" --time="$PHASE0_VALIDATION_TIME" \
    --job-name=pb0-validate --output="$run_dir/logs/validation-%j.out" --export=ALL \
    "$script_path" _validate "$run_dir" "$PHASE0_RECOMMENDED_JULIA_THREADS" \
    "$PHASE0_RECOMMENDED_BACKEND")"
  job_id="${raw%%;*}"
  printf 'validation\tchi%s\t%s\t%s\t%s\t%sG\t%s\n' \
    "$PHASE0_VALIDATION_CHI" "$PHASE0_RECOMMENDED_BACKEND" \
    "$PHASE0_RECOMMENDED_JULIA_THREADS" "$PHASE0_RECOMMENDED_SLURM_CPUS" \
    "$validation_memory_gib" "$job_id" >>"$run_dir/jobs.tsv"

  local report_raw report_id
  report_raw="$(sbatch --parsable \
    --account="$PHASE0_ACCOUNT" --constraint=cpu --qos="$PHASE0_QOS" \
    --nodes=1 --ntasks=1 --cpus-per-task=2 --mem=2G \
    --time="$PHASE0_REPORT_TIME" --job-name=pb0-final-report \
    --dependency="afterany:$job_id" --kill-on-invalid-dep=yes \
    --output="$run_dir/logs/final-report-%j.out" --export=ALL \
    "$script_path" _report "$run_dir")"
  report_id="${report_raw%%;*}"
  printf 'report\tfinal-report\tserial\t1\t2\t2G\t%s\n' "$report_id" >>"$run_dir/jobs.tsv"

  cat <<EOF
Submitted chi=$PHASE0_VALIDATION_CHI validation job $job_id
Backend: $PHASE0_RECOMMENDED_BACKEND
Julia threads: $PHASE0_RECOMMENDED_JULIA_THREADS
Slurm logical CPUs: $PHASE0_RECOMMENDED_SLURM_CPUS
Memory safety request: ${validation_memory_gib}G
Automatic final report: $report_id
EOF
}

run_validation_worker() {
  local run_dir="$1"
  local threads="$2"
  local backend="$3"
  load_run_environment "$run_dir"
  [[ -n "${SLURM_JOB_ID:-}" ]] || die "_validate must run inside a Slurm allocation"
  [[ -f "$run_dir/seed_state.h5" ]] || die "missing seed state"
  set_thread_environment "$threads" "$backend"
  run_timed_julia_payload "$run_dir/metrics/validation.time" "$threads" \
    validate "$run_dir" "$threads" "$backend" "$PHASE0_VALIDATION_CHI"
}

usage() {
  cat <<EOF
Usage:
  bash $(basename "$script_path") plan
  bash $(basename "$script_path") submit [RUN_ID]
  bash $(basename "$script_path") status [RUN_ID|RUN_DIR]
  bash $(basename "$script_path") show [RUN_ID|RUN_DIR]
  bash $(basename "$script_path") report [RUN_ID|RUN_DIR]
  bash $(basename "$script_path") validate [RUN_ID|RUN_DIR]

Recommended Perlmutter workflow:
  1. Put this file in project_b_flux_dimensional_reduction/slurm/.
  2. Load or select Julia 1.12 and instantiate the Project.toml environment.
  3. Run 'plan', then 'submit'. The seed, matrix, and report are dependency-linked.
  4. Run 'show' after completion, then 'validate' for one chi=$PHASE0_VALIDATION_CHI check.

Useful overrides:
  PHASE0_ACCOUNT=m4863
  PHASE0_JULIA=/absolute/path/to/julia
  PROJECT_B_DIR=/absolute/path/to/project_b_flux_dimensional_reduction

The default workflow has a ${PHASE0_MAX_NODE_HOURS}-node-hour Phase 0 ceiling inside the
${PHASE0_PROJECT_BUDGET_NODE_HOURS}-node-hour Project B budget. No production scan is submitted.
EOF
}

command_name="${1:-help}"
case "$command_name" in
  plan)
    print_plan
    ;;
  submit)
    submit_phase0 "${2:-}"
    ;;
  status)
    status_phase0 "${2:-}"
    ;;
  show)
    show_phase0 "${2:-}"
    ;;
  report)
    manual_report_phase0 "${2:-}"
    ;;
  validate)
    submit_validation "${2:-}"
    ;;
  _seed)
    [[ "$#" -eq 2 ]] || die "internal _seed argument mismatch"
    run_seed_worker "$2"
    ;;
  _bench)
    [[ "$#" -eq 5 ]] || die "internal _bench argument mismatch"
    run_benchmark_worker "$2" "$3" "$4" "$5"
    ;;
  _report)
    [[ "$#" -eq 2 ]] || die "internal _report argument mismatch"
    generate_report "$2"
    ;;
  _validate)
    [[ "$#" -eq 4 ]] || die "internal _validate argument mismatch"
    run_validation_worker "$2" "$3" "$4"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    die "unknown command: $command_name"
    ;;
esac

exit 0

: <<'__PHASE0_JULIA_PAYLOAD__'
#= BEGIN_PHASE0_JULIA_PAYLOAD =#

using Printf
using LinearAlgebra
using ITensors
using ITensorMPS
using TriangularJ1J2ProjectB

const PB = TriangularJ1J2ProjectB

parse_int(text, name) = try
    parse(Int, text)
catch
    error("$name must be an integer, got '$text'")
end

function write_result(path::AbstractString, pairs::Pair...)
    temporary = path * ".tmp"
    ispath(path) && error("refusing to overwrite result: $path")
    ispath(temporary) && error("stale temporary result: $temporary")
    open(temporary, "w") do io
        for (key, value) in pairs
            text = replace(string(value), '\n' => ' ')
            println(io, key, "=", text)
        end
    end
    mv(temporary, path)
    return path
end

function phase0_model()
    return ModelSettings(
        geometry=YCGeometry(6, 1),
        J1=1.0,
        J2=0.12,
        Delta1=1.0,
        Delta2=1.0,
        Bz=0.0,
        twist_gauge=:uniform,
        mps_period=2,
    )
end

function phase0_runtime(output_directory::AbstractString, backend::AbstractString, threads::Int)
    backend in ("serial", "blocksparse", "strided", "blas") ||
        error("unknown threading backend '$backend'")
    return RuntimeSettings(
        output_directory=String(output_directory),
        blas_threads=backend == "blas" ? threads : 1,
        strided_threads=backend == "strided" ? threads : 1,
        threaded_blocksparse=backend == "blocksparse",
        output_level=1,
    )
end

function phase0_optimizer(maxdim::Int, max_iterations::Int; residual_tol=1e-30)
    return OptimizerSettings(
        maxdim=maxdim,
        cutoff=1e-10,
        residual_tol=residual_tol,
        max_iterations=max_iterations,
        max_growth_steps=16,
        solver_tol_scale=100.0,
        solver_tol_floor=1e-10,
        multisite_update_alg="sequential",
        require_converged=false,
        divergence_patience=max(max_iterations + 1, 8),
        divergence_factor=4.0,
    )
end

function seed_settings(run_dir::AbstractString, maxdim::Int)
    model = phase0_model()
    # The corrected two-site YC6-1 seed reaches chi=256 cleanly but required
    # about 64 iterations on Perlmutter to cross 1e-5. Keep the physical
    # convergence gate and provide headroom; the optimizer exits immediately
    # once the target is reached, so this does not force 80 iterations.
    optimizer = phase0_optimizer(maxdim, 80; residual_tol=1e-5)
    optimizer = OptimizerSettings(
        maxdim=optimizer.maxdim,
        cutoff=optimizer.cutoff,
        residual_tol=optimizer.residual_tol,
        max_iterations=optimizer.max_iterations,
        max_growth_steps=optimizer.max_growth_steps,
        solver_tol_scale=optimizer.solver_tol_scale,
        solver_tol_floor=optimizer.solver_tol_floor,
        multisite_update_alg=optimizer.multisite_update_alg,
        require_converged=true,
        divergence_patience=optimizer.divergence_patience,
        divergence_factor=optimizer.divergence_factor,
    )
    scan = ScanSettings(
        branch="phase0_seed",
        fluxes_over_pi=[0.0],
        seed_pattern="alternating",
        random_seed=1,
        adaptive_bisection=false,
        minimum_step_over_pi=1 / 64,
        save_rejected=false,
        initial_state_file=nothing,
    )
    spectrum = SpectrumSettings(
        physical_sz_sectors=[0.0],
        neigs=1,
        tolerance=1e-8,
        krylov_dimension=4,
        random_seed=1,
    )
    runtime = phase0_runtime(run_dir, "blocksparse", Threads.nthreads())
    config_text = "phase0 calibration seed; YC6-1; theta/pi=0; chi=$maxdim; mps_period=2; twist_gauge=uniform"
    return ProjectSettings(
        model=model,
        optimizer=optimizer,
        scan=scan,
        spectrum=spectrum,
        runtime=runtime,
        config_path=ENV["PHASE0_SCRIPT_PATH"],
        config_text=config_text,
    )
end

function run_seed(run_dir::AbstractString, maxdim::Int)
    mkpath(joinpath(run_dir, "metrics"))
    settings = seed_settings(run_dir, maxdim)
    PB.configure_threading!(settings.runtime)
    psi = build_product_state(settings)
    hamiltonian = build_hamiltonian(settings.model, siteinds(psi), 0.0)
    elapsed = @elapsed begin
        psi, diagnostic = PB.grow_and_optimize(
            hamiltonian,
            psi,
            settings.optimizer;
            output_level=settings.runtime.output_level,
        )
    end
    diagnostic.converged || error(
        "calibration seed did not converge: residual=$(diagnostic.residual), " *
        "minimum=$(diagnostic.minimum_residual)",
    )
    maxlinkdim(psi) >= maxdim || error(
        "calibration seed reached chi=$(maxlinkdim(psi)), expected at least $maxdim",
    )
    state_path = joinpath(run_dir, "seed_state.h5")
    PB.write_state_file(
        state_path,
        settings,
        psi,
        hamiltonian,
        diagnostic,
        0.0,
        1;
        continuation_accepted=true,
    )
    write_result(
        joinpath(run_dir, "metrics", "seed.result"),
        "status" => "ok",
        "maxdim" => maxlinkdim(psi),
        "mps_period" => PB.nsites(psi),
        "minimal_mps_period" => minimal_mps_period(settings.model.geometry),
        "twist_gauge" => settings.model.twist_gauge,
        "unit_cell_status" => PB.nsites(psi) == minimal_mps_period(settings.model.geometry) ? "minimal" : "legacy_supercell",
        "iterations" => diagnostic.iterations,
        "kernel_seconds" => elapsed,
        "final_residual" => diagnostic.residual,
        "minimum_residual" => diagnostic.minimum_residual,
        "stop_reason" => diagnostic.stop_reason,
        "julia_threads" => Threads.nthreads(),
        "blas_threads" => BLAS.get_num_threads(),
        "state_path" => state_path,
    )
    println("PHASE0_SEED_COMPLETE state=$state_path elapsed=$elapsed")
    return nothing
end

function run_benchmark(
    run_dir::AbstractString,
    label::AbstractString,
    requested_threads::Int,
    backend::AbstractString,
    warmup_iterations::Int,
    measured_iterations::Int,
)
    Threads.nthreads() == requested_threads || error(
        "Julia started with $(Threads.nthreads()) threads, expected $requested_threads",
    )
    state = PB.read_state_file(joinpath(run_dir, "seed_state.h5"))
    psi = state.psi
    runtime = phase0_runtime(run_dir, backend, requested_threads)
    active = PB.configure_threading!(runtime)
    model = phase0_model()
    hamiltonian = build_hamiltonian(model, siteinds(psi), state.theta_over_pi)
    maxdim = maxlinkdim(psi)
    actual_period = PB.nsites(psi)
    minimum_period = minimal_mps_period(model.geometry)

    warmup_optimizer = phase0_optimizer(maxdim, warmup_iterations)
    GC.gc()
    warmup_seconds = @elapsed begin
        psi, warmup = PB.run_vumps_iterations(
            hamiltonian,
            psi,
            warmup_optimizer;
            output_level=1,
        )
    end
    length(warmup.residual_history) == warmup_iterations || error(
        "warm-up stopped after $(warmup.iterations) iterations",
    )

    measured_optimizer = phase0_optimizer(maxdim, measured_iterations)
    GC.gc()
    kernel_seconds = @elapsed begin
        psi, measured = PB.run_vumps_iterations(
            hamiltonian,
            psi,
            measured_optimizer;
            output_level=1,
        )
    end
    measured.iterations == measured_iterations || error(
        "measurement stopped after $(measured.iterations) iterations",
    )
    all(isfinite, measured.residual_history) || error("non-finite benchmark residual")

    result_path = joinpath(run_dir, "metrics", "$label.result")
    write_result(
        result_path,
        "status" => "ok",
        "label" => label,
        "backend" => backend,
        "requested_threads" => requested_threads,
        "julia_threads" => Threads.nthreads(),
        "blas_threads" => BLAS.get_num_threads(),
        "strided_threads" => active.strided,
        "threaded_blocksparse" => active.blocksparse,
        "maxdim" => maxlinkdim(psi),
        "mps_period" => actual_period,
        "minimal_mps_period" => minimum_period,
        "twist_gauge" => state.twist_gauge,
        "unit_cell_status" => actual_period == minimum_period ? "minimal" : "legacy_supercell",
        "warmup_iterations" => warmup.iterations,
        "warmup_seconds" => warmup_seconds,
        "iterations" => measured.iterations,
        "kernel_seconds" => kernel_seconds,
        "seconds_per_iteration" => kernel_seconds / measured.iterations,
        "initial_residual" => first(measured.residual_history),
        "final_residual" => measured.residual,
        "minimum_residual" => measured.minimum_residual,
    )
    println(
        "PHASE0_BENCHMARK_COMPLETE label=$label backend=$backend " *
        "threads=$requested_threads seconds=$kernel_seconds",
    )
    return nothing
end

function run_validation(
    run_dir::AbstractString,
    requested_threads::Int,
    backend::AbstractString,
    target_maxdim::Int,
)
    Threads.nthreads() == requested_threads || error(
        "Julia started with $(Threads.nthreads()) threads, expected $requested_threads",
    )
    state = PB.read_state_file(joinpath(run_dir, "seed_state.h5"))
    psi = state.psi
    runtime = phase0_runtime(run_dir, backend, requested_threads)
    active = PB.configure_threading!(runtime)
    model = phase0_model()
    hamiltonian = build_hamiltonian(model, siteinds(psi), state.theta_over_pi)

    GC.gc()
    growth_seconds = @elapsed begin
        for growth_step in 1:4
            old_dimension = maxlinkdim(psi)
            old_dimension >= target_maxdim && break
            psi = PB.subspace_expansion(
                psi,
                hamiltonian;
                maxdim=target_maxdim,
                cutoff=1e-10,
            )
            new_dimension = maxlinkdim(psi)
            new_dimension > old_dimension || error(
                "subspace expansion stalled at chi=$old_dimension",
            )
        end
    end
    maxlinkdim(psi) >= target_maxdim || error(
        "validation reached chi=$(maxlinkdim(psi)), expected $target_maxdim",
    )

    optimizer = phase0_optimizer(target_maxdim, 1)
    GC.gc()
    kernel_seconds = @elapsed begin
        psi, diagnostic = PB.run_vumps_iterations(
            hamiltonian,
            psi,
            optimizer;
            output_level=1,
        )
    end
    diagnostic.iterations == 1 || error("validation did not complete exactly one iteration")
    isfinite(diagnostic.residual) || error("validation residual is not finite")

    write_result(
        joinpath(run_dir, "metrics", "validation.result"),
        "status" => "ok",
        "backend" => backend,
        "requested_threads" => requested_threads,
        "julia_threads" => Threads.nthreads(),
        "blas_threads" => BLAS.get_num_threads(),
        "strided_threads" => active.strided,
        "threaded_blocksparse" => active.blocksparse,
        "maxdim" => maxlinkdim(psi),
        "mps_period" => PB.nsites(psi),
        "minimal_mps_period" => minimal_mps_period(model.geometry),
        "twist_gauge" => state.twist_gauge,
        "unit_cell_status" => PB.nsites(psi) == minimal_mps_period(model.geometry) ? "minimal" : "legacy_supercell",
        "growth_seconds" => growth_seconds,
        "iterations" => diagnostic.iterations,
        "kernel_seconds" => kernel_seconds,
        "final_residual" => diagnostic.residual,
    )
    println(
        "PHASE0_VALIDATION_COMPLETE chi=$(maxlinkdim(psi)) backend=$backend " *
        "threads=$requested_threads seconds=$kernel_seconds",
    )
    return nothing
end

function main(args)
    isempty(args) && error("missing payload mode")
    mode = first(args)
    if mode == "seed"
        length(args) == 3 || error("seed payload expects RUN_DIR CHI")
        run_seed(args[2], parse_int(args[3], "seed chi"))
    elseif mode == "benchmark"
        length(args) == 7 || error(
            "benchmark payload expects RUN_DIR LABEL THREADS BACKEND WARMUP_ITERS MEASURED_ITERS",
        )
        run_benchmark(
            args[2],
            args[3],
            parse_int(args[4], "thread count"),
            args[5],
            parse_int(args[6], "warm-up iterations"),
            parse_int(args[7], "measured iterations"),
        )
    elseif mode == "validate"
        length(args) == 5 || error("validate payload expects RUN_DIR THREADS BACKEND TARGET_CHI")
        run_validation(
            args[2],
            parse_int(args[3], "thread count"),
            args[4],
            parse_int(args[5], "target chi"),
        )
    else
        error("unknown payload mode '$mode'")
    end
    return nothing
end

main(ARGS)

#= END_PHASE0_JULIA_PAYLOAD =#
__PHASE0_JULIA_PAYLOAD__
