# Called in the batch allocation, before any srun step. The task request is
# not necessarily the allocated CPU count; record and check both separately.
thread_benchmark_allocation() {
  local ceiling="$1" step="$2" nodes="${SLURM_JOB_NUM_NODES:-${SLURM_NNODES:-}}"
  local allocated="${SLURM_JOB_CPUS_PER_NODE:-}" task="${SLURM_CPUS_PER_TASK:-}"
  [[ "$nodes" == 1 && -n "${SLURM_JOB_ID:-}" ]] || {
    echo 'ERROR: benchmark requires a one-node Slurm allocation' >&2; return 2;
  }
  [[ "$allocated" =~ ^([1-9][0-9]*)(\(x1\))?$ ]] || {
    printf 'ERROR: invalid SLURM_JOB_CPUS_PER_NODE=%s\n' "$allocated" >&2; return 2;
  }
  allocated="${BASH_REMATCH[1]}"
  [[ "$task" =~ ^[1-9][0-9]*$ ]] || {
    printf 'ERROR: invalid SLURM_CPUS_PER_TASK=%s\n' "$task" >&2; return 2;
  }
  # 34 is the modeled 64G floor; 36 is the observed grant, now fully budgeted.
  ((allocated>=34 && allocated<=ceiling && allocated%2==0 && task>=step && task<=allocated)) || {
    printf 'ERROR: allocation outside sealed bounds: allocated=%s task=%s step=%s CPU_ceiling=%s\n' \
      "$allocated" "$task" "$step" "$ceiling" >&2; return 2;
  }
  printf '%s\n' "$allocated"
}
