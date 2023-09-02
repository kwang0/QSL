#!/bin/bash -l
#SBATCH --account=pc_gpumoore
#SBATCH --partition=es1
#SBATCH --qos=es_normal
#SBATCH --nodes=1
#SBATCH --time=72:00:00
#SBATCH --mail-user=kwang98@berkeley.edu
#SBATCH --mem=187GB
#SBATCH --exclusive

#SBATCH --gres=gpu:V100:1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2

julia $1 $2 $3 $4 $5 > logs_gpu/C${2}_J${3}_chi${4}_dt${5}_unnormed.txt
# julia $1 $2 $3 $4 $5 > logs_gpu/square_C${2}_chi${4}_dt${5}_double_evolve.txt

exit 0
