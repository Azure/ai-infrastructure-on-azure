#!/bin/bash
#SBATCH --job-name=thermal_test
#SBATCH -p gpu
#SBATCH --mem=0
#SBATCH --ntasks-per-node=1
#SBATCH --output=thermal_test.%J.out
#SBATCH --error=thermal_test.%J.err

###############################################################################
# Thermal stress test — runs dcgmproftester on every GPU and collects
# temperature / power / throttle telemetry via nvidia-smi.
#
# Pass --gpus-per-node on the sbatch command line:
#   sbatch --gpus-per-node=8 -w ccw-gpu-[1-10] thermal_test.slurm   # H100
#   sbatch --gpus-per-node=4 -w ccw-gpu-[1-10] thermal_test.slurm   # GB300
###############################################################################

# Run the thermal test script on each node
srun --ntasks-per-node=1 --export=ALL /bin/bash ./thermal_test.sh
