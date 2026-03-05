#!/bin/bash
###############################################################################
# NCCL all_reduce test launcher
#
# Reads a generation config from configs/<gen>.conf, then calls sbatch with
# the correct resource directives. Auto-detects GPU generation from nvidia-smi
# when --sku is omitted and -w (nodelist) is given.
#
# Usage:
#   ./nccl_test.sh --sku graceblackwell -N 4
#   ./nccl_test.sh --sku hopper -N 8 -w ccw-gpu-[1-8]
#   ./nccl_test.sh -N 4 -w ccw-gpu-[1-4]            # auto-detect from node
#
#   # Quick bandwidth check (large messages only, 10 iterations):
#   ./nccl_test.sh --sku graceblackwell --begin-size 16G --end-size 16G \
#                  --iters 10 -N 18
#
# Options:
#   --sku NAME          GPU generation config name (e.g. hopper, graceblackwell)
#   --begin-size SIZE   Start message size  (default: 1K)
#   --end-size SIZE     End message size    (default: 16G)
#   --iters N           Iterations per size (default: all_reduce_perf default)
#   --check             Enable data validation (default: off)
#
# All other arguments are passed through to sbatch.
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Parse our options, collect everything else for sbatch
# ---------------------------------------------------------------------------
SKU=""
BEGIN_SIZE="1K"
END_SIZE="16G"
ITERS=""
CHECK=0
SBATCH_ARGS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--sku)        SKU="$2";        shift 2 ;;
		--begin-size) BEGIN_SIZE="$2";  shift 2 ;;
		--end-size)   END_SIZE="$2";    shift 2 ;;
		--iters)      ITERS="$2";       shift 2 ;;
		--check)      CHECK=1;          shift   ;;
		*)            SBATCH_ARGS+=("$1"); shift ;;
	esac
done

# ---------------------------------------------------------------------------
# Auto-detect GPU generation if --sku not given — probe a node from -w arg
# ---------------------------------------------------------------------------
if [ -z "$SKU" ]; then
	NODE=""
	PREV=""
	for i in "${SBATCH_ARGS[@]}"; do
		if [[ "$PREV" == "-w" || "$PREV" == "--nodelist" ]]; then
			NODE=$(scontrol show hostnames "$i" 2>/dev/null | head -1)
			break
		elif [[ "$i" == --nodelist=* ]]; then
			NODE=$(scontrol show hostnames "${i#--nodelist=}" 2>/dev/null | head -1)
			break
		elif [[ "$i" == -w* && ${#i} -gt 2 ]]; then
			NODE=$(scontrol show hostnames "${i#-w}" 2>/dev/null | head -1)
			break
		fi
		PREV="$i"
	done

	if [ -n "$NODE" ]; then
		GPU_NAME=$(ssh "$NODE" "nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1" 2>/dev/null || true)
		case "$GPU_NAME" in
			*H100*|*H200*)              SKU="hopper"         ;;
			*GB200*|*GB300*)            SKU="graceblackwell" ;;
		esac
	fi

	if [ -z "$SKU" ]; then
		echo "ERROR: Cannot auto-detect GPU generation. Use --sku or provide -w <nodelist>."
		echo "  e.g.  $0 --sku graceblackwell -N 4"
		echo "  e.g.  $0 -N 4 -w ccw-gpu-[1-4]"
		echo ""
		echo "Available configs:"
		ls "${SCRIPT_DIR}/configs/"*.conf 2>/dev/null | sed 's|.*/||;s|\.conf||' | sed 's/^/  /'
		exit 1
	fi
fi

# ---------------------------------------------------------------------------
# Load generation config
# ---------------------------------------------------------------------------
CONF="${SCRIPT_DIR}/configs/${SKU}.conf"
if [ ! -f "$CONF" ]; then
	echo "ERROR: Config not found: $CONF"
	echo "Available configs:"
	ls "${SCRIPT_DIR}/configs/"*.conf 2>/dev/null | sed 's|.*/||;s|\.conf||' | sed 's/^/  /'
	exit 1
fi
source "$CONF"

for var in GPUS_PER_NODE TASKS_PER_NODE CPUS_PER_TASK; do
	if [ -z "${!var:-}" ]; then
		echo "ERROR: $var not set in $CONF"
		exit 1
	fi
done

echo "=== NCCL all_reduce test launcher ==="
echo "  Generation  : ${SKU}"
echo "  GPUs/node   : ${GPUS_PER_NODE}"
echo "  Tasks/node  : ${TASKS_PER_NODE}"
echo "  CPUs/task   : ${CPUS_PER_TASK}"
echo "  Begin size  : ${BEGIN_SIZE}"
echo "  End size    : ${END_SIZE}"
echo "  Iterations  : ${ITERS:-default}"
echo "  Data check  : ${CHECK}"
echo ""

# ---------------------------------------------------------------------------
# Submit with correct resource directives from the config
# ---------------------------------------------------------------------------
EXPORT_VARS="NONE,SKU=${SKU},NCCL_BEGIN_SIZE=${BEGIN_SIZE},NCCL_END_SIZE=${END_SIZE},NCCL_CHECK=${CHECK}"
if [ -n "$ITERS" ]; then
	EXPORT_VARS="${EXPORT_VARS},NCCL_ITERS=${ITERS}"
fi

sbatch \
	--gpus-per-node="${GPUS_PER_NODE}" \
	--ntasks-per-node="${TASKS_PER_NODE}" \
	--cpus-per-task="${CPUS_PER_TASK}" \
	--export="${EXPORT_VARS}" \
	"${SBATCH_ARGS[@]}" \
	"${SCRIPT_DIR}/nccl_test.slurm"
