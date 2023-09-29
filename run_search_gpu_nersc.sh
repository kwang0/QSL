#!/bin/bash
#SBATCH -A m3341_g
#SBATCH -C gpu&hbm80g
#SBATCH -q shared
#SBATCH -t 24:00:00
#SBATCH -n 1
#SBATCH -c 32
#SBATCH --gpus-per-task=1

export SLURM_CPU_BIND="cores"

julia $1 $2 $3 $4 $5 $6 > logs_gpu/ground_state_search_C${2}_L${3}_J${4}_1Delta${5}_2Delta${5}_chi${6}.txt
# julia $1 $2 $3 $4 $5 > logs_gpu/square_C${2}_chi${4}_dt${5}_double_evolve.txt

exit 0
