#!/bin/bash
#SBATCH -A m4863_g
#SBATCH -C gpu&hbm80g
#SBATCH -q regular
#SBATCH -N 5
#SBATCH -t 6:00:00
#SBATCH --ntasks-per-node=4
#SBATCH --licenses=scratch
#SBATCH -o ./logs_slurm/slurm-%j.out

export SLURM_CPU_BIND="cores"

for i in $(seq 0.4 0.4 8.0)
do
    srun --exact -u -n 1 --gpus-per-task 1 -c 32 --mem-per-gpu=55G julia ground_state_search.jl 6 36 0.12 $i 1.35 512 > logs_gpu/ground_state_search_C6_L36_J0.12_B0.0_Bperp${i}_1Delta1.35_2Delta1.35_chi512.txt &
done

wait
