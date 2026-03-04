#!/bin/bash
###############################################################################
# GPU GEMM (ubergemm) performance test launcher
#
# Reads a generation config from configs/<gen>.conf, then calls sbatch with
# the correct resource directives. Auto-detects GPU generation if not set.
#
# Usage:
#   ./gpu_test.sh -N 4                                    # auto-detect
#   ./gpu_test.sh -N 4 -w ccw-gpu-[1-4]                   # specific nodes
#   SKU=graceblackwell ./gpu_test.sh -N 4                       # explicit
#   SKU=graceblackwell ./gpu_test.sh -N 4 -w ccw-gpu-[1-4]     # explicit + nodes
#
# Any additional arguments are passed through to sbatch.
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Auto-detect GPU generation if not set — try to ssh to a node from -w arg
# ---------------------------------------------------------------------------
if [ -z "${SKU:-}" ]; then
	# Try to extract a node name from -w argument for auto-detection
	NODE=""
	PREV=""
	for i in "$@"; do
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

	if [ -z "${SKU:-}" ]; then
		echo "ERROR: Cannot auto-detect GPU generation. Set SKU= or provide -w <nodelist>."
		echo "  e.g.  SKU=graceblackwell $0 -N 4"
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
	"$@" \
	"${SCRIPT_DIR}/gpu_test.slurm"
