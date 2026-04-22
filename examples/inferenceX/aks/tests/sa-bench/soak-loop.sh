#!/bin/bash
set -e

DURATION_SECS=3600
END_TIME=$(($(date +%s) + DURATION_SECS))
ITERATION=0
WORK_DIR="/tmp/sa-bench"
RESULT_DIR="/tmp/results/soak-test"
mkdir -p "$RESULT_DIR"

echo "Soak test started at $(date). Will run until $(date -d @$END_TIME)."
echo "---"

while [ $(date +%s) -lt $END_TIME ]; do
	ITERATION=$((ITERATION + 1))
	echo "=== Iteration $ITERATION started at $(date) ==="

	python3 -u "${WORK_DIR}/benchmark_serving.py" \
		--model "deepseek-r1-0528-fp4-v2" --tokenizer "/tmp/tokenizer/" \
		--host localhost --port 8000 \
		--backend dynamo --endpoint /v1/completions \
		--disable-tqdm \
		--dataset-name random \
		--num-prompts 240 \
		--random-input-len 8192 \
		--random-output-len 1024 \
		--random-range-ratio 0.8 \
		--ignore-eos \
		--request-rate inf \
		--percentile-metrics ttft,tpot,itl,e2el \
		--max-concurrency 24 \
		--use-chat-template \
		--save-result --result-dir "$RESULT_DIR" \
		--result-filename "soak_iter_${ITERATION}.json"

	echo "=== Iteration $ITERATION completed at $(date) ==="
	echo "---"
done

echo "Soak test finished after $ITERATION iterations at $(date)."
