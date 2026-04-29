#!/bin/bash
#SBATCH -A m4863
#SBATCH -C cpu
#SBATCH -c 256
#SBATCH -q regular
#SBATCH -N 1
#SBATCH -t 24:00:00
#SBATCH -o ./logs_slurm/slurm-%j.out

module load julia
module load cray-mpich
module load libfabric

export OMP_NUM_THREADS=256
export MKL_NUM_THREADS=256

C=${1:-6}
L=${2:-36}
J2=${3:-0.12}
DELTA=${4:-1.0}
THETA_PI=${5:-1.0}
MAXDIM=${6:-512}
NFLUX=${7:-9}
NSWEEPS=${8:-10}
YC_SHIFT=${9:-0}

LOG="logs_cpu/ground_state_search_flux_threaded_YC${C}-${YC_SHIFT}_L${L}_J${J2}_1Delta${DELTA}_2Delta${DELTA}_thetaPi${THETA_PI}_bothgaps_chi${MAXDIM}.txt"
julia --heap-size-hint=400G ground_state_search_flux_threaded.jl \
    "$C" "$L" "$J2" "$DELTA" "$THETA_PI" "$MAXDIM" \
    "$NFLUX" "$NSWEEPS" "$YC_SHIFT" >> "$LOG"

exit 0
