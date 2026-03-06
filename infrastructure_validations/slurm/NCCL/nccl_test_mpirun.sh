#!/bin/bash
###############################################################################
# NCCL all_reduce test (mpirun launcher)
#
# Reads a generation config from configs/<gen>.conf.
# Auto-detects GPU generation from nvidia-smi on the first host if not set.
#
# Usage:
#   ./nccl_test_mpirun.sh --sku graceblackwell ccw-gpu-[1-10]
#   ./nccl_test_mpirun.sh ccw-gpu-[1-10]              # auto-detect
#
#   # Quick bandwidth check:
#   ./nccl_test_mpirun.sh --sku graceblackwell --begin-size 16G \
#                          --end-size 16G --iters 10 ccw-gpu-[1-18]
#
# Options:
#   --sku NAME          GPU generation config name
#   --begin-size SIZE   Start message size  (default: 1K)
#   --end-size SIZE     End message size    (default: 16G)
#   --iters N           Iterations per size (default: all_reduce_perf default)
#   --check             Enable data validation (default: off)
#
# The last positional argument is the Slurm-style nodelist.
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Parse options
# ---------------------------------------------------------------------------
SKU=""
BEGIN_SIZE="1K"
END_SIZE="16G"
ITERS=""
CHECK=0
NODELIST=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--sku)        SKU="$2";        shift 2 ;;
		--begin-size) BEGIN_SIZE="$2";  shift 2 ;;
		--end-size)   END_SIZE="$2";    shift 2 ;;
		--iters)      ITERS="$2";       shift 2 ;;
		--check)      CHECK=1;          shift   ;;
		-*)           echo "Unknown option: $1"; exit 1 ;;
		*)            NODELIST="$1";    shift   ;;
	esac
done

if [ -z "$NODELIST" ]; then
	echo "Usage: $0 [options] <slurm_nodelist>"
	echo "  e.g. $0 --sku graceblackwell ccw-gpu-[1-10]"
	exit 1
fi

# ---------------------------------------------------------------------------
# Expand hostlist and pick the first node for auto-detection
# ---------------------------------------------------------------------------
HOSTFILE=$(mktemp /tmp/nccl_hostfile.XXXXXX)
trap 'rm -f "$HOSTFILE"' EXIT
scontrol show hostnames "$NODELIST" > "$HOSTFILE"
SCALE=$(wc -l < "$HOSTFILE")
FIRST_HOST=$(head -1 "$HOSTFILE")

# ---------------------------------------------------------------------------
# Auto-detect GPU generation from nvidia-smi on the first host if not set
# ---------------------------------------------------------------------------
if [ -z "$SKU" ]; then
	GPU_NAME=$(ssh "$FIRST_HOST" "nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1" 2>/dev/null || true)
	case "$GPU_NAME" in
		*H100*|*H200*)              SKU="hopper"         ;;
		*GB200*|*GB300*)            SKU="graceblackwell" ;;
	esac

	if [ -z "$SKU" ]; then
		echo "ERROR: Cannot auto-detect GPU generation. Use --sku."
		echo "  e.g.  $0 --sku graceblackwell ccw-gpu-[1-10]"
		echo ""
		echo "Available configs:"
		ls "${SCRIPT_DIR}/configs/"*.conf 2>/dev/null | sed 's|.*/||;s|\.conf||' | sed 's/^/  /'
		exit 1
	fi
fi

# ---------------------------------------------------------------------------
# Load system profile and MPI before sourcing config so that
# LD_LIBRARY_PATH etc. are available for any config-time checks.
# ---------------------------------------------------------------------------
set +u  # system profile scripts may use unbound variables
source /etc/profile
module load mpi/hpcx
set -u

# ---------------------------------------------------------------------------
# Load generation config — all NCCL/MPI env vars live here.
# ---------------------------------------------------------------------------
CONF="${SCRIPT_DIR}/configs/${SKU}.conf"
if [ ! -f "$CONF" ]; then
	echo "ERROR: Config not found: $CONF"
	echo "Available configs:"
	ls "${SCRIPT_DIR}/configs/"*.conf 2>/dev/null | sed 's|.*/||;s|\.conf||' | sed 's/^/  /'
	exit 1
fi

source "$CONF"

for var in GPUS_PER_NODE TASKS_PER_NODE CPUS_PER_TASK CPU_BIND; do
	if [ -z "${!var:-}" ]; then
		echo "ERROR: $var not set in $CONF"
		exit 1
	fi
done

echo "=== NCCL all_reduce test (mpirun) ==="
echo "  Generation  : ${SKU}"
echo "  Nodes       : ${SCALE}"
echo "  GPUs/node   : ${GPUS_PER_NODE}"
echo "  Tasks/node  : ${TASKS_PER_NODE}"
echo "  CPUs/task   : ${CPUS_PER_TASK}"
echo "  CPU bind    : ${CPU_BIND}"
echo "  Total GPUs  : $((SCALE * GPUS_PER_NODE))"
echo "  Begin size  : ${BEGIN_SIZE}"
echo "  End size    : ${END_SIZE}"
echo "  Iterations  : ${ITERS:-default}"
echo "  Data check  : ${CHECK}"

# ---------------------------------------------------------------------------
# Build -x flags from all exported NCCL/UCX/SHARP/etc. env vars set by config
# ---------------------------------------------------------------------------
ENV_FLAGS=()
for var in $(compgen -e | grep -E '^(NCCL_|SHARP_|UCX_|MELLANOX_|CUDA_|OMPI_)' | sort); do
	ENV_FLAGS+=( -x "${var}=${!var}" )
done

# ---------------------------------------------------------------------------
# Map CPU_BIND to mpirun --bind-to syntax
# ---------------------------------------------------------------------------
if [ "$CPU_BIND" = "none" ]; then
	BIND_ARGS=( --bind-to none )
else
	# mask_cpu: binding — pass through as cpu-list / slot-list
	BIND_ARGS=( --bind-to none )
fi

# ---------------------------------------------------------------------------
# Build all_reduce_perf arguments
# ---------------------------------------------------------------------------
PERF_ARGS=( -b "$BEGIN_SIZE" -e "$END_SIZE" -f 2 -g 1 -c "$CHECK" )
if [ -n "$ITERS" ]; then
	PERF_ARGS+=( -n "$ITERS" )
fi

mpirun -np $((SCALE * GPUS_PER_NODE)) \
	--map-by "ppr:${GPUS_PER_NODE}:node" \
	-hostfile "$HOSTFILE" \
	-mca plm_rsh_no_tree_spawn 1 \
	-mca plm_rsh_num_concurrent 800 \
	-mca coll_hcoll_enable 0 \
	"${BIND_ARGS[@]}" \
	-x LD_LIBRARY_PATH \
	"${ENV_FLAGS[@]}" \
	/opt/nccl-tests/build/all_reduce_perf "${PERF_ARGS[@]}"
