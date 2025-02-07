#!/bin/bash
#SBATCH -A m4863_g
#SBATCH -C gpu&hbm80g
#SBATCH -q regular
#SBATCH -N 4
#SBATCH -t 24:00:00
#SBATCH --ntasks-per-node=4
#SBATCH --licenses=scratch
#SBATCH -o ./logs_slurm/slurm-%j.out

export SLURM_CPU_BIND="cores"

# for i in $(seq 0.0 0.5 1.5)
for i in $(seq 0.0 0.8 3.2)
do
    srun --exact -u -n 1 --gpus-per-task 1 -c 32 --mem-per-gpu=55G julia J1_J2_triangular_gpu.jl 6 36 0.12 $i 1.35 512 0.1 transverse > logs_gpu/C6_L36_J0.12_B${i}_1Delta1.35_2Delta1.35_chi512_dt0.1_transverse_gssearched_twositetdvp.txt &
    srun --exact -u -n 1 --gpus-per-task 1 -c 32 --mem-per-gpu=55G julia J1_J2_triangular_gpu.jl 6 36 0.12 $i 1.35 512 0.1 transversedown > logs_gpu/C6_L36_J0.12_B${i}_1Delta1.35_2Delta1.35_chi512_dt0.1_transversedown_gssearched_twositetdvp.txt &
    srun --exact -u -n 1 --gpus-per-task 1 -c 32 --mem-per-gpu=55G julia J1_J2_triangular_gpu.jl 6 36 0.12 $i 1.35 512 0.1 longitudinal > logs_gpu/C6_L36_J0.12_B${i}_1Delta1.35_2Delta1.35_chi512_dt0.1_longitudinal_gssearched_twositetdvp.txt &
done

wait
