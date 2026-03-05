#!/bin/bash
###############################################################################
# GPU GEMM (ubergemm) performance test launcher
#
# Reads a generation config from configs/<gen>.conf, then calls sbatch with
# the correct resource directives. Auto-detects GPU generation from nvidia-smi
# when --sku is omitted and -w (nodelist) is given.
#
# Usage:
#   ./gpu_test.sh --sku graceblackwell -N 4
#   ./gpu_test.sh --sku hopper -N 8 -w ccw-gpu-[1-8]
#   ./gpu_test.sh -N 4 -w ccw-gpu-[1-4]            # auto-detect from node
#
# Options:
#   --sku NAME    GPU generation config name (e.g. hopper, graceblackwell)
#
# All other arguments are passed through to sbatch.
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Parse our options, collect everything else for sbatch
# ---------------------------------------------------------------------------
SKU=""
SBATCH_ARGS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--sku)  SKU="$2"; shift 2 ;;
		*)      SBATCH_ARGS+=("$1"); shift ;;
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

for var in GPUS_PER_NODE UBERGEMM_PATH TEST_DURATION; do
	if [ -z "${!var:-}" ]; then
		echo "ERROR: $var not set in $CONF"
		exit 1
	fi
done

echo "=== GPU GEMM (ubergemm) test launcher ==="
echo "  Generation    : ${SKU}"
echo "  GPUs/node     : ${GPUS_PER_NODE}"
echo "  Test duration : ${TEST_DURATION}s per GPU"
echo "  ubergemm path : ${UBERGEMM_PATH}"
echo ""

# ---------------------------------------------------------------------------
# Submit with correct resource directives from the config
# ---------------------------------------------------------------------------
sbatch \
	--gpus-per-node="${GPUS_PER_NODE}" \
	--ntasks-per-node=1 \
	--export="NONE,SKU=${SKU}" \
	"${SBATCH_ARGS[@]}" \
	"${SCRIPT_DIR}/gpu_test.slurm"
