#!/bin/bash
#SBATCH --job-name=health_check
#SBATCH -p gpu
#SBATCH --mem=0
#SBATCH --ntasks-per-node=1
#SBATCH --output=job_%J.out
#SBATCH --error=job_%J.err

# Run the health check script and save output
srun --ntasks-per-node=1 --exclusive bash -c '
    LOG_FILE="$(hostname).log"
    sudo bash /opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh > "$LOG_FILE" 2>&1
    echo "### Infiniband Firmware Version ###" >> "$LOG_FILE"
    cat /sys/class/infiniband/mlx5_ib*/fw_ver >> "$LOG_FILE" 2>&1
'
