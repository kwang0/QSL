#!/bin/bash -l
#SBATCH --account=lr_oppie
#SBATCH --partition=lr6
#SBATCH --qos=condo_oppie
#SBATCH --nodes=1
#SBATCH --time=72:00:00
#SBATCH --mail-user=kwang98@berkeley.edu
#SBATCH --mem=128GB
#SBATCH --exclusive

#SBATCH --cpus-per-task=40

export OMP_NUM_THREADS=40
export MKL_NUM_THREADS=40
julia --heap-size-hint=100G $1 $2 $3 $4 $5 > logs/C${2}_J${3}_chi${4}_dt${5}_unnormed.txt

exit 0
