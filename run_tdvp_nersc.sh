#!/bin/bash
#SBATCH -A m3341
#SBATCH -C cpu
#SBATCH -c 256
#SBATCH -q regular
#SBATCH -N 1
#SBATCH -t 24:00:00

export OMP_NUM_THREADS=256
export MKL_NUM_THREADS=256
julia --heap-size-hint=400G $1 $2 $3 $4 $5 $6 $7 $8 $9 > logs_cpu/C${2}_L${3}_J${4}_B${5}_1Delta${6}_2Delta${6}_chi${7}_dt${8}_${9}_disconnectfirst_onesitetdvp.txt

exit 0
