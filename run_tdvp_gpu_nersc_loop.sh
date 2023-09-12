#!/bin/bash
#SBATCH -A m3341_g
#SBATCH -C gpu&hbm80g
#SBATCH -q regular
#SBATCH -N 7
#SBATCH -t 24:00:00
#SBATCH --ntasks-per-node=4

export SLURM_CPU_BIND="cores"

for i in $(seq 0.5 .25 1.5)
do
    for j in $(seq 0.5 .25 1.5)
    do
        srun --exact -u -n 1 --gpus-per-task 1 -c 32 --mem-per-gpu=55G julia J1_J2_triangular_gpu.jl 6 0.072 $i $j 512 0.1 > logs_gpu/C6_J0.072_1Delta${i}_2Delta${j}_chi512_dt0.1.txt &
    done
done

wait
