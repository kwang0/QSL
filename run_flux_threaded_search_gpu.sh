#!/bin/bash
#SBATCH -A m4863_g
#SBATCH -C gpu&hbm80g
#SBATCH -q shared
#SBATCH -t 6:00:00
#SBATCH -n 1
#SBATCH -c 32
#SBATCH --gpus-per-task=1
#SBATCH --licenses=scratch
#SBATCH -o ./logs_slurm/slurm-%j.out

module load julia
module load cudatoolkit
module load cray-mpich
module load libfabric

export SLURM_CPU_BIND="cores"

C=${1:-6}
L=${2:-36}
J2=${3:-0.12}
DELTA=${4:-1.0}
THETA_PI=${5:-1.0}
MAXDIM=${6:-512}
NFLUX=${7:-9}
NSWEEPS_INITIAL=${8:-10}
NSWEEPS_INTERMEDIATE=${9:-2}
NSWEEPS_FINAL=${10:-10}
YC_SHIFT=${11:-0}

LOG="logs_gpu/ground_state_search_flux_threaded_YC${C}-${YC_SHIFT}_L${L}_J${J2}_1Delta${DELTA}_2Delta${DELTA}_thetaPi${THETA_PI}_gap_chi${MAXDIM}.txt"
julia ground_state_search_flux_threaded.jl \
    "$C" "$L" "$J2" "$DELTA" "$THETA_PI" "$MAXDIM" \
    "$NFLUX" "$NSWEEPS_INITIAL" "$NSWEEPS_INTERMEDIATE" "$NSWEEPS_FINAL" "$YC_SHIFT" true >> "$LOG"

exit 0
