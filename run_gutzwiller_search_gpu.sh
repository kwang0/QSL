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

julia ground_state_search_gutzwiller.jl 6 36 512 > logs_gpu/gutzwiller_ground_state_search_YC_C6_L36_Jrange_1Delta1.0_2Delta1.0_chi512.txt

exit 0