#!/bin/bash
#SBATCH -A m4863
#SBATCH -C cpu
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=64
#SBATCH -q shared
#SBATCH -N 1
#SBATCH --mem=128G
#SBATCH -t 48:00:00
#SBATCH -J vumps-flux-cpu
#SBATCH -o ./logs_slurm/slurm-%j.out

set -euo pipefail

module load julia

cd "${SLURM_SUBMIT_DIR:-$PWD}"
mkdir -p logs_cpu logs_slurm

C=${1:-6}
J2=${2:-0.12}
THETA_PI=${3:-2.0}
MAXDIM=${4:-512}
NFLUX=${5:-17}
YC_SHIFT=${6:-0}
CUTOFF=${7:-1e-10}
VUMPS_TOL=${8:-1e-5}
MAX_VUMPS_ITERS=${9:-20}
NEIGS=${10:-16}
DEFAULT_OUTPUT_DIR="${PSCRATCH:-/pscratch/sd/k/kwang98}/QSL"
OUTPUT_DIR="${11:-$DEFAULT_OUTPUT_DIR}"

CPUS_PER_TASK="${SLURM_CPUS_PER_TASK:-64}"
BLAS_THREADS="${BLAS_THREADS:-1}"
ITENSOR_STRIDED_THREADS="${ITENSOR_STRIDED_THREADS:-1}"
JULIA_NUM_THREADS="${JULIA_NUM_THREADS:-32}"
HEAP_SIZE_HINT="${HEAP_SIZE_HINT:-100G}"

export JULIA_NUM_THREADS
export JULIA_NUM_BLAS_THREADS="$BLAS_THREADS"
export OMP_NUM_THREADS="$BLAS_THREADS"
export MKL_NUM_THREADS="$BLAS_THREADS"
export OPENBLAS_NUM_THREADS="$BLAS_THREADS"
export BLIS_NUM_THREADS="$BLAS_THREADS"
export VECLIB_MAXIMUM_THREADS="$BLAS_THREADS"
export ITENSOR_STRIDED_THREADS
export OMP_PROC_BIND="${OMP_PROC_BIND:-spread}"
export OMP_PLACES="${OMP_PLACES:-threads}"
export OMP_DYNAMIC=FALSE
export MKL_DYNAMIC=FALSE
export JULIA_PKG_PRECOMPILE_AUTO="${JULIA_PKG_PRECOMPILE_AUTO:-0}"

mkdir -p "$OUTPUT_DIR"

JOB_TAG="ground_state_search_flux_threaded_vumps_YC${C}-${YC_SHIFT}_J${J2}_thetaPi${THETA_PI}_chi${MAXDIM}_nflux${NFLUX}"
LOG="logs_cpu/${JOB_TAG}_${SLURM_JOB_ID:-manual}.txt"

{
    echo "Job started: $(date)"
    echo "Host: $(hostname)"
    echo "SLURM_JOB_ID: ${SLURM_JOB_ID:-manual}"
    echo "SLURM_CPUS_PER_TASK: ${SLURM_CPUS_PER_TASK:-unset}"
    echo "C=$C J2=$J2 theta/pi=$THETA_PI maxdim=$MAXDIM nflux=$NFLUX yc_shift=$YC_SHIFT"
    echo "cutoff=$CUTOFF vumps_tol=$VUMPS_TOL max_vumps_iters=$MAX_VUMPS_ITERS neigs=$NEIGS"
    echo "output_dir=$OUTPUT_DIR"
    echo "Julia threads=$JULIA_NUM_THREADS BLAS threads=$BLAS_THREADS ITensor Strided threads=$ITENSOR_STRIDED_THREADS"
    echo "OMP_PROC_BIND=$OMP_PROC_BIND OMP_PLACES=$OMP_PLACES"
    echo
} > "$LOG"

srun \
    -n 1 \
    -c "$CPUS_PER_TASK" \
    --cpu-bind=cores \
    julia \
    --heap-size-hint="$HEAP_SIZE_HINT" \
    --startup-file=no \
    -t "$JULIA_NUM_THREADS" \
    ground_state_search_flux_threaded_vumps.jl \
    "$C" "$J2" "$THETA_PI" "$MAXDIM" "$NFLUX" "$YC_SHIFT" \
    "$CUTOFF" "$VUMPS_TOL" "$MAX_VUMPS_ITERS" "$NEIGS" "$OUTPUT_DIR" \
    >> "$LOG" 2>&1

echo "Job finished: $(date)" >> "$LOG"
