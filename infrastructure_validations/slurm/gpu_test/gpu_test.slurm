#!/bin/bash
#SBATCH -p gpu
#SBATCH --exclusive
#SBATCH --time=00:30:00
#SBATCH --output=gpu_test.%J.out

###############################################################################
# GPU GEMM (ubergemm) performance test  (batch script)
#
# Do NOT call sbatch directly on this file — use the launcher instead:
#   ./gpu_test.sh -N 4
#   SKU=graceblackwell ./gpu_test.sh -N 4 -w ccw-gpu-[1-4]
#
# The launcher reads configs/<gen>.conf and passes --gpus-per-node and
# --export=SKU to sbatch.
###############################################################################

set -euo pipefail

# SKU is passed via --export from the launcher
if [ -z "${SKU:-}" ]; then
	echo "ERROR: SKU not set. Use the launcher: ./gpu_test.sh -N <nodes>"
	exit 1
fi

# Load generation config
SCRIPT_PATH=$(scontrol show job "$SLURM_JOB_ID" | grep -oP 'Command=\K\S+')
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
CONF="${SCRIPT_DIR}/configs/${SKU}.conf"

if [ ! -f "$CONF" ]; then
	echo "ERROR: Config not found: $CONF"
	exit 1
fi

source "$CONF"

echo "=== GPU GEMM (ubergemm) performance test ==="
echo "  Generation    : ${SKU}"
echo "  Nodes         : ${SLURM_JOB_NUM_NODES}"
echo "  GPUs/node     : ${GPUS_PER_NODE}"
echo "  Test duration : ${TEST_DURATION}s per GPU"
echo "  ubergemm      : ${UBERGEMM_PATH}"
echo ""

# ---------------------------------------------------------------------------
# Function to run ubergemm on all GPUs of a single node in parallel
# ---------------------------------------------------------------------------
run_node_test() {
	TMPDIR=$(mktemp -d)

	for gpu in $(seq 0 $((NUM_GPUS - 1))); do
		(
			output=$($UBERGEMM --adapters "$gpu" --time_to_run "$TEST_DURATION" 2>&1)
			gflops=$(echo "$output" | grep "GFlops:" | grep -v "GFlops:0" | \
				sed 's/.*GFlops:\([0-9.e+]*\).*/\1/' | \
				awk '{ sum += $1; count++ } END { if (count > 0) printf "%.0f", sum/count; else print "0" }')
			echo "$gflops" > "$TMPDIR/gpu$gpu"
		) &
	done

	wait

	# Collect results in order
	results="$(hostname)"
	for gpu in $(seq 0 $((NUM_GPUS - 1))); do
		gflops=$(cat "$TMPDIR/gpu$gpu" 2>/dev/null || echo "0")
		results="$results,$gflops"
	done

	rm -rf "$TMPDIR"
	echo "$results"
}

export -f run_node_test
export UBERGEMM="$UBERGEMM_PATH"
export TEST_DURATION
export NUM_GPUS="$GPUS_PER_NODE"

# ---------------------------------------------------------------------------
# Print CSV header
# ---------------------------------------------------------------------------
header="hostname"
for gpu in $(seq 0 $((GPUS_PER_NODE - 1))); do
	header="$header,gpu${gpu}_gflops"
done
echo "$header"

# ---------------------------------------------------------------------------
# Run on all allocated nodes
# ---------------------------------------------------------------------------
srun --export=ALL --ntasks-per-node=1 /bin/bash -c 'run_node_test'
