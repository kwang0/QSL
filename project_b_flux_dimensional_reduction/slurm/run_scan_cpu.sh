#!/bin/bash
#SBATCH --job-name=project-b-scan
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=24:00:00
#SBATCH --output=output/logs/%x-%j.out

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: sbatch slurm/run_scan_cpu.sh CONFIG.toml" >&2
  exit 2
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_dir/output/logs"
export JULIA_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
exec "${JULIA_BIN:-julia}" --project="$project_dir" --startup-file=no \
  "$project_dir/scripts/run_scan.jl" "$1"
