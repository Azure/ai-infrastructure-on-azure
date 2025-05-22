#!/bin/bash
#SBATCH --job-name=health_check
#SBATCH -p gpu
#SBATCH --mem=0
#SBATCH --ntasks-per-node=1
#SBATCH --output=job_%J.out
#SBATCH --error=job_%J.err

# Run the thermal test script and save output
srun --ntasks-per-node=1 --exclusive bash thermal_test.sh
