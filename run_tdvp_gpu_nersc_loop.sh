#!/bin/bash
#SBATCH -A m3341_g
#SBATCH -C gpu&hbm80g
#SBATCH -q regular
#SBATCH -N 1
#SBATCH -t 24:00:00
#SBATCH --ntasks-per-node=4

export SLURM_CPU_BIND="cores"

for i in $(seq 0.5 0.5 2.0)
do
    srun --exact -u -n 1 --gpus-per-task 1 -c 32 --mem-per-gpu=55G julia J1_J2_triangular_gpu.jl 6 36 0.03 $i 1.0 512 0.1 > logs_gpu/C6_L36_J0.03_B${i}_1Delta1.0_2Delta1.0_chi512_dt0.1.txt &
done

wait
