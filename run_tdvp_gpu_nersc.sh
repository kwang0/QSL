#!/bin/bash
#SBATCH -A m3341_g
#SBATCH -C gpu&hbm80g
#SBATCH -q shared
#SBATCH -t 24:00:00
#SBATCH -n 1
#SBATCH -c 32
#SBATCH --gpus-per-task=1

export SLURM_CPU_BIND="cores"

julia $1 $2 $3 $4 $5 > logs_gpu/C${2}_J${3}_chi${4}_dt${5}.txt
# julia $1 $2 $3 $4 $5 > logs_gpu/square_C${2}_chi${4}_dt${5}_double_evolve.txt

exit 0
