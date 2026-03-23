#!/bin/bash
#SBATCH -p gpu
#SBATCH --exclusive
#SBATCH --ntasks-per-node=1
#SBATCH --time=00:30:00
#SBATCH --output=gpu_test.%J.out

###############################################################################
# GPU GEMM (ubergemm) performance test
#
# Pass --gpus-per-node on the sbatch command line:
#   sbatch --gpus-per-node=4 -N 4 gpu_test.slurm                    # GB300
#   sbatch --gpus-per-node=8 -N 8 -w ccw-gpu-[1-8] gpu_test.slurm   # H100
###############################################################################

set -euo pipefail

UBERGEMM="/usr/libexec/datacenter-gpu-manager-4/plugins/cuda13/updated/ubergemm"
TEST_DURATION=60
NUM_GPUS="${SLURM_GPUS_ON_NODE:-8}"

echo "=== GPU GEMM (ubergemm) performance test ==="
echo "  Nodes         : ${SLURM_JOB_NUM_NODES}"
echo "  GPUs/node     : ${NUM_GPUS}"
echo "  Test duration : ${TEST_DURATION}s per GPU"
echo "  ubergemm      : ${UBERGEMM}"
echo ""

# ---------------------------------------------------------------------------
# Function to run ubergemm on all GPUs of a single node in parallel
# ---------------------------------------------------------------------------
run_node_test() {
	TMPDIR=$(mktemp -d)

	for gpu in $(seq 0 $((NUM_GPUS - 1))); do
		(
			output=$($UBERGEMM --adapters "$gpu" --time_to_run "$TEST_DURATION" 2>&1)
			# Parse GFlops from lines after "starting...." (steady-state only)
			# Output format: GFlops:1.7933e+06
			gflops=$(echo "$output" |
				sed -n '/starting/,$p' |
				grep -oP 'GFlops:[0-9.e+]+' |
				sed 's/GFlops://' |
				awk '{ sum += $1; count++ } END { if (count > 0) printf "%.0f", sum/count; else print "0" }')
			echo "$gflops" >"$TMPDIR/gpu$gpu"
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
export UBERGEMM TEST_DURATION NUM_GPUS

# ---------------------------------------------------------------------------
# Print CSV header
# ---------------------------------------------------------------------------
header="hostname"
for gpu in $(seq 0 $((NUM_GPUS - 1))); do
	header="$header,gpu${gpu}_gflops"
done
echo "$header"

# ---------------------------------------------------------------------------
# Run on all allocated nodes
# ---------------------------------------------------------------------------
srun --export=ALL --ntasks-per-node=1 /bin/bash -c 'run_node_test'
