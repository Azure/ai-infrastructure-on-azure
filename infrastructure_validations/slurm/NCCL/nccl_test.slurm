#!/bin/bash
#SBATCH -p gpu
#SBATCH --exclusive
#SBATCH --output=nccl_test.%J.out

###############################################################################
# NCCL all_reduce test  (batch script)
#
# Do NOT call sbatch directly on this file — use the launcher instead:
#   ./nccl_test.sh --sku graceblackwell -N 4
#   ./nccl_test.sh --sku hopper -N 8 -w ccw-gpu-[1-8]
#
# The launcher reads configs/<gen>.conf and passes the correct --gpus-per-node,
# --ntasks-per-node, --cpus-per-task, and --export variables to sbatch.
###############################################################################

set -euo pipefail

# SKU is passed via --export from the launcher
if [ -z "${SKU:-}" ]; then
	echo "ERROR: SKU not set. Use the launcher: ./nccl_test.sh --sku <name> -N <nodes>"
	exit 1
fi

# Test parameters (passed via --export from launcher, with defaults)
NCCL_BEGIN_SIZE="${NCCL_BEGIN_SIZE:-1K}"
NCCL_END_SIZE="${NCCL_END_SIZE:-16G}"
NCCL_ITERS="${NCCL_ITERS:-}"
NCCL_CHECK="${NCCL_CHECK:-0}"

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
echo "  Generation  : ${SKU}"
echo "  Nodes       : ${SLURM_JOB_NUM_NODES}"
echo "  GPUs/node   : ${SLURM_GPUS_PER_NODE:-${GPUS_PER_NODE}}"
echo "  Tasks/node  : ${SLURM_NTASKS_PER_NODE}"
echo "  CPUs/task   : ${SLURM_CPUS_PER_TASK}"
echo "  CPU bind    : ${CPU_BIND}"
echo "  Begin size  : ${NCCL_BEGIN_SIZE}"
echo "  End size    : ${NCCL_END_SIZE}"
echo "  Iterations  : ${NCCL_ITERS:-default}"
echo "  Data check  : ${NCCL_CHECK}"

# ---------------------------------------------------------------------------
# Build all_reduce_perf arguments
# ---------------------------------------------------------------------------
PERF_ARGS=( -b "$NCCL_BEGIN_SIZE" -e "$NCCL_END_SIZE" -f 2 -g 1 -c "$NCCL_CHECK" )
if [ -n "$NCCL_ITERS" ]; then
	PERF_ARGS+=( -n "$NCCL_ITERS" )
fi

srun --mpi=pmix \
	--export=ALL \
	--cpu-bind="${CPU_BIND}" \
	--mem=0 \
	/opt/nccl-tests/build/all_reduce_perf "${PERF_ARGS[@]}"
