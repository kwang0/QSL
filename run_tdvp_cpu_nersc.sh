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

julia --heap-size-hint=400G J1_J2_triangular_cpu.jl $1 $2 $3 $4 $5 $6 $7 >> logs_cpu/C${1}_L${2}_J${3}_1Delta${4}_2Delta${4}_chi${5}_dt${6}_${7}.txt
# julia $1 $2 $3 $4 $5 $6 $7 $8 $9 > logs_gpu/C${2}_L${3}_J${4}_B${5}_1Delta${6}_2Delta${6}_chi${7}_dt${8}_${9}.txt
# julia $1 $2 $3 $4 $5 > logs_gpu/square_C${2}_chi${4}_dt${5}_double_evolve.txt

exit 0
