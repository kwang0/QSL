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

export SLURM_CPU_BIND="cores"

julia ground_state_search.jl 6 36 0.043 1.0 512 > logs_gpu/ground_state_search_YC_C6_L36_J0.043_1Delta1.0_2Delta1.0_chi512.txt

exit 0