#!/bin/bash
#SBATCH -p gpu
#SBATCH --exclusive
#SBATCH --output=job.%J.out

###############################################################################
# NCCL all_reduce test  (batch script)
#
# Do NOT call sbatch directly on this file — use the launcher instead:
#   ./nccl_test.sh -N 4
#   SKU=graceblackwell ./nccl_test.sh -N 4 -w ccw-gpu-[1-4]
#
# The launcher reads configs/<gen>.conf and passes the correct --gpus-per-node,
# --ntasks-per-node, --cpus-per-task, and --export=SKU to sbatch.
###############################################################################

set -euo pipefail

# SKU is passed via --export from the launcher
if [ -z "${SKU:-}" ]; then
	echo "ERROR: SKU not set. Use the launcher: ./nccl_test.sh -N <nodes>"
	exit 1
fi

# Load generation config for NCCL environment variables and CPU_BIND
SCRIPT_PATH=$(scontrol show job "$SLURM_JOB_ID" | grep -oP 'Command=\K\S+')
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
CONF="${SCRIPT_DIR}/configs/${SKU}.conf"

if [ ! -f "$CONF" ]; then
	echo "ERROR: Config not found: $CONF"
	exit 1
fi

# ---------------------------------------------------------------------------
# Load system profile and MPI before sourcing config so that
# LD_LIBRARY_PATH etc. are available for any config-time checks.
# ---------------------------------------------------------------------------
set +u  # system profile scripts may use unbound variables
source /etc/profile
module load mpi/hpcx
set -u

# Source the generation config — all NCCL/MPI env vars live here.
source "$CONF"

echo "=== NCCL all_reduce test ==="
echo "  Generation : ${SKU}"
echo "  Nodes      : ${SLURM_JOB_NUM_NODES}"
echo "  GPUs/node  : ${SLURM_GPUS_PER_NODE:-${GPUS_PER_NODE}}"
echo "  Tasks/node : ${SLURM_NTASKS_PER_NODE}"
echo "  CPUs/task  : ${SLURM_CPUS_PER_TASK}"
echo "  CPU bind   : ${CPU_BIND}"

srun --mpi=pmix \
	--export=ALL \
	--cpu-bind="${CPU_BIND}" \
	--mem=0 \
	/opt/nccl-tests/build/all_reduce_perf -b 1K -e 16G -f 2 -g 1 -c 0
