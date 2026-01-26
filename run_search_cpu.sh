#!/bin/bash
#SBATCH -A m4863
#SBATCH -C cpu
#SBATCH -c 256
#SBATCH -q regular
#SBATCH -N 1
#SBATCH -t 24:00:00
#SBATCH -o ./logs_slurm/slurm-%j.out

module load julia
module load cudatoolkit
module load cray-mpich
module load libfabric

export OMP_NUM_THREADS=256
export MKL_NUM_THREADS=256
julia --heap-size-hint=400G ground_state_search_cpu.jl $1 $2 $3 $4 $5 >> logs_cpu/ground_state_search_C${1}_L${2}_J${3}_1Delta${4}_2Delta${4}_chi${5}.txt

exit 0