#!/bin/bash
#SBATCH -A m4863_g
#SBATCH -C gpu&hbm80g
#SBATCH -q shared
#SBATCH -t 24:00:00
#SBATCH -n 1
#SBATCH -c 32
#SBATCH --gpus-per-task=1
#SBATCH --licenses=scratch
#SBATCH -o ./logs_slurm/slurm-%j.out

export SLURM_CPU_BIND="cores"

module load julia
module load cudatoolkit
module load cray-mpich
module load libfabric

julia create_u1_ansatz.jl $1 $2 $3 >> logs_gpu/create_u1_ansatz_YC_C${1}_L${2}_chi${3}.txt

exit 0