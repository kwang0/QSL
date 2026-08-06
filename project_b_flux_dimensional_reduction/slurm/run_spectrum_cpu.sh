#!/bin/bash
#SBATCH --job-name=project-b-spectrum
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=12:00:00
#SBATCH --output=output/logs/%x-%j.out

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: sbatch slurm/run_spectrum_cpu.sh CONFIG.toml [STATE.h5 ...]" >&2
  exit 2
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_dir/output/logs"
export JULIA_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
exec "${JULIA_BIN:-julia}" --project="$project_dir" --startup-file=no \
  "$project_dir/scripts/run_spectrum.jl" "$@"
