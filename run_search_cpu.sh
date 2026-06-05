#!/bin/bash
#SBATCH -A m4863
#SBATCH -C cpu
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=64
#SBATCH -q regular
#SBATCH -N 1
#SBATCH -t 48:00:00
#SBATCH -o ./logs_slurm/slurm-%j.out

module load julia

export JULIA_NUM_THREADS=32
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

srun -n 1 -c ${SLURM_CPUS_PER_TASK} --cpu-bind=cores \
    julia --heap-size-hint=400G -t ${JULIA_NUM_THREADS} ground_state_search_cpu.jl "$@" \
    >> logs_cpu/ground_state_search_C${1}_L${2}_J${3}_1Delta${4}_2Delta${4}_chi${5}.txt

exit 0
