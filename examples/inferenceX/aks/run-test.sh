#!/usr/bin/env bash
# InferenceX AKS Benchmark Runner — sa-bench edition.
#
# Deploys a helm release matching a test config (tests/<engine>/<sku>-<precision>/
# <isl>k<osl>k/<spec>/conc-*.yaml), waits for workers to come up, copies the
# sa-bench tool onto the frontend pod, runs it, pulls back the result JSON,
# and compares achieved throughput against the official InferenceX reference
# (fetched via aks/tests/fetch-references.sh).
#
# Usage:
#   ./run-test.sh tests/trtllm/gb300-fp4/8k1k/mtp/conc-5.yaml
#   ./run-test.sh tests/trtllm/gb300-fp4/8k1k/mtp/conc-180.yaml -t   # teardown after
#   ./run-test.sh tests/trtllm/gb300-fp4/8k1k/mtp/conc-666.yaml -s   # skip deploy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_DIR="${SCRIPT_DIR}/helm/inferencex"
TESTS_DIR="${SCRIPT_DIR}/tests"
SA_BENCH_DIR="${TESTS_DIR}/sa-bench"
RESULTS_DIR="${SCRIPT_DIR}/results"
NAMESPACE="inferencex"
MODEL_NAME="deepseek-r1-0528-fp4-v2"
TOKENIZER_PATH="/tmp/tokenizer"
TEARDOWN=false
SKIP_DEPLOY=false
DRY_RUN=false
SKIP_STATS=false
POLL_INTERVAL=30
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

usage() {
  cat <<'EOF'
Usage: run-test.sh <test-config> [OPTIONS]

  <test-config>   Path to a test YAML under tests/<engine>/<sku>-<precision>/...
                  (e.g. tests/trtllm/gb300-fp4/8k1k/mtp/conc-5.yaml)

Options:
  -n NAMESPACE   Kubernetes namespace (default: inferencex)
  -t             Teardown helm release after benchmark
  -s             Skip deploy (assume chart already running with correct config)
  -d             Dry run — print commands without executing
  -S             Skip Prometheus stats + plots collection at end
  -h             Show this help

Stats collection (default ON):
  After the benchmark completes, run-test.sh invokes
  scripts/collect-prom-stats.py and scripts/plot-prom-stats.py to query
  in-cluster Prometheus and regenerate per-recipe stats and plots. Requires
  a port-forward to Prometheus at localhost:9090, e.g.:

    kubectl -n monitoring port-forward \
      svc/kube-prometheus-kube-prome-prometheus 9090:9090 &

  If Prometheus is not reachable the step is auto-skipped. Pass -S to skip
  unconditionally.

Examples:
  ./run-test.sh tests/trtllm/gb300-fp4/8k1k/mtp/conc-5.yaml
  ./run-test.sh tests/trtllm/gb300-fp4/8k1k/mtp/conc-180.yaml -t
  ./run-test.sh tests/trtllm/gb300-fp4/8k1k/mtp/conc-666.yaml -s
EOF
  exit 0
}

parse_yaml_value() {
  local file="$1" key="$2"
  grep "^${key}:" "$file" | head -1 | sed "s/^${key}:[[:space:]]*//" | sed 's/[[:space:]]*#.*//'
}

if [[ $# -lt 1 || "$1" == "-h" ]]; then usage; fi

CONFIG="$1"; shift
[[ -f "$CONFIG" ]] || { echo "ERROR: Config file not found: $CONFIG"; exit 1; }

while getopts "n:tsdSh" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    t) TEARDOWN=true ;;
    s) SKIP_DEPLOY=true ;;
    d) DRY_RUN=true ;;
    S) SKIP_STATS=true ;;
    h) usage ;;
    *) usage ;;
  esac
done

NAME=$(parse_yaml_value "$CONFIG" "name")
VALUES_FILE=$(parse_yaml_value "$CONFIG" "values_file")
CONC=$(parse_yaml_value "$CONFIG" "concurrency")
ISL=$(parse_yaml_value "$CONFIG" "isl")
OSL=$(parse_yaml_value "$CONFIG" "osl")
TOTAL_GPUS=$(parse_yaml_value "$CONFIG" "total_gpus")
PREFILL_GPUS=$(parse_yaml_value "$CONFIG" "prefill_gpus_each")
DECODE_GPUS=$(parse_yaml_value "$CONFIG" "decode_gpus_each")
RECIPE=$(parse_yaml_value "$CONFIG" "recipe")
SKU=$(parse_yaml_value "$CONFIG" "sku")
PRECISION=$(parse_yaml_value "$CONFIG" "precision")
SPEC_METHOD=$(parse_yaml_value "$CONFIG" "spec_method")
IX_DATE=$(parse_yaml_value "$CONFIG" "inferencex_date")
IX_FETCHED=$(parse_yaml_value "$CONFIG" "inferencex_fetched")
IX_TOK_GPU=$(parse_yaml_value "$CONFIG" "inferencex_tput_per_gpu")
IX_OUT_TOK_GPU=$(parse_yaml_value "$CONFIG" "inferencex_output_tput_per_gpu")
IX_MED_TPOT=$(parse_yaml_value "$CONFIG" "inferencex_median_tpot_ms")
IX_MED_TTFT=$(parse_yaml_value "$CONFIG" "inferencex_median_ttft_ms")

echo "═══════════════════════════════════════════════════════════════"
echo "  InferenceX AKS Benchmark: ${NAME}"
echo "═══════════════════════════════════════════════════════════════"
echo "  Recipe:       ${RECIPE}"
echo "  SKU/Prec:     ${SKU} / ${PRECISION} / ${SPEC_METHOD}"
echo "  Values:       ${VALUES_FILE}"
echo "  Concurrency:  ${CONC}"
echo "  GPUs:         ${TOTAL_GPUS} (prefill=${PREFILL_GPUS}/worker, decode=${DECODE_GPUS}/worker)"
echo "  ISL/OSL:      ${ISL}/${OSL}"
echo "  Tool:         sa-bench (benchmark_serving.py + dynamo backend)"
echo "  InferenceX:   ${IX_TOK_GPU} tok/s/GPU  (official, date=${IX_DATE})"
echo "═══════════════════════════════════════════════════════════════"
echo ""

run_cmd() {
  if $DRY_RUN; then
    echo "[DRY RUN] $*"
  else
    "$@"
  fi
}

# ------- Instrumentation helpers -------------------------------------------
# LOCAL_DIR is created early in main() and used by log_event + record_* helpers.
LOCAL_DIR=""

# Emit an event line to timings.txt with the current UTC timestamp (ISO-8601).
# Usage: log_event <EVENT_NAME> [optional-value]
log_event() {
  local event="$1"; shift || true
  local extra="${*:-}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [[ -n "$LOCAL_DIR" ]]; then
    if [[ -n "$extra" ]]; then
      printf '%s\t%s\t%s\n' "$ts" "$event" "$extra" >> "${LOCAL_DIR}/timings.txt"
    else
      printf '%s\t%s\n' "$ts" "$event" >> "${LOCAL_DIR}/timings.txt"
    fi
  fi
  echo "  [event ${ts}] ${event}${extra:+  $extra}"
}

# Capture pod placement: one row per pod (name, role, node, GPU indices, start time).
# Written as TSV for easy parsing / Grafana annotation.
record_pod_placement() {
  [[ -n "$LOCAL_DIR" ]] || return 0
  local out="${LOCAL_DIR}/pod-placement.tsv"
  echo -e "pod\trole\tnode\tgpu_indices\tstart_time" > "$out"

  local tmp="${LOCAL_DIR}/.pods.json"
  if ! kubectl get pods -n "$NAMESPACE" -o json > "$tmp" 2>/dev/null; then
    echo "  WARNING: kubectl get pods failed; skipping placement record."
    rm -f "$tmp"
    return 0
  fi
  python3 - "$out" "$tmp" <<'PY' || echo "  WARNING: failed to parse pod placement (non-fatal)."
import json, sys
out_path, in_path = sys.argv[1], sys.argv[2]
with open(in_path) as f:
    data = json.load(f)
rows = []
for p in data.get("items", []):
    name = p["metadata"]["name"]
    labels = p["metadata"].get("labels", {}) or {}
    role = labels.get("app.kubernetes.io/component", "-")
    node = (p.get("spec") or {}).get("nodeName", "-")
    start = (p.get("status") or {}).get("startTime", "-")
    gpu_idx = "-"
    for c in (p.get("spec") or {}).get("containers", []):
        env = {e.get("name"): e.get("value") for e in (c.get("env") or []) if e.get("value") is not None}
        if "NVIDIA_VISIBLE_DEVICES" in env:
            gpu_idx = env["NVIDIA_VISIBLE_DEVICES"]; break
        res = ((c.get("resources") or {}).get("limits") or {})
        for k, v in res.items():
            if "gpu" in k.lower():
                gpu_idx = f"count={v}"; break
        if gpu_idx != "-": break
    rows.append((name, role, node, gpu_idx, start))
rows.sort(key=lambda r: (r[1], r[0]))
with open(out_path, "a") as f:
    for r in rows:
        f.write("\t".join(r) + "\n")
PY
  rm -f "$tmp"
  echo "  Wrote ${out} ($(($(wc -l < "$out") - 1)) pods)"
}

# Wait for the model-distribution MPIJob launcher to reach Succeeded/Failed.
# Extracts rank-0 timing markers from the launcher pod logs into timings.txt.
wait_for_distribution() {
  echo ">>> Waiting for model-distribute MPIJob to complete..."
  log_event "DISTRIBUTE_WAIT_START"

  local max_wait=3600 elapsed=0 poll=20
  local launcher_pod=""

  while (( elapsed < max_wait )); do
    launcher_pod=$(kubectl get pods -n "$NAMESPACE" \
      -l app.kubernetes.io/component=model-distribution-launcher \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -n "$launcher_pod" ]]; then
      local phase
      phase=$(kubectl get pod -n "$NAMESPACE" "$launcher_pod" \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
      if [[ "$phase" == "Succeeded" ]]; then
        echo "  Distribution launcher ${launcher_pod} Succeeded."
        log_event "DISTRIBUTE_COMPLETE" "pod=${launcher_pod}"
        break
      fi
      if [[ "$phase" == "Failed" ]]; then
        echo "ERROR: Distribution launcher ${launcher_pod} Failed."
        kubectl logs -n "$NAMESPACE" "$launcher_pod" --tail=80 || true
        log_event "DISTRIBUTE_FAILED" "pod=${launcher_pod}"
        exit 1
      fi
      echo "  [${elapsed}s] distribute launcher ${launcher_pod} phase=${phase}"
    else
      echo "  [${elapsed}s] waiting for distribute launcher pod to appear..."
    fi
    sleep "$poll"
    elapsed=$((elapsed + poll))
  done

  if (( elapsed >= max_wait )); then
    echo "ERROR: Distribution did not complete within ${max_wait}s"
    exit 1
  fi

  # Persist full launcher log + rank-0 phase markers (with kubectl timestamps).
  if [[ -n "$LOCAL_DIR" && -n "$launcher_pod" ]]; then
    kubectl logs -n "$NAMESPACE" --timestamps -c launcher "$launcher_pod" \
      > "${LOCAL_DIR}/distribute-launcher.log" 2>/dev/null || true
    grep -E '\[rank=0\] (Checking blob cache at|Found in blob cache, downloading with azcopy|Downloading from HuggingFace|Download attempt [0-9]+/[0-9]+|Starting MPI barrier and file broadcast|[0-9]+ rank\(s\) need data, starting broadcast|Broadcasting [0-9]+ files to [0-9]+ peers|Distribution complete|Model distribution finished)' \
      "${LOCAL_DIR}/distribute-launcher.log" \
      > "${LOCAL_DIR}/distribute-markers.log" 2>/dev/null || true
    if [[ -s "${LOCAL_DIR}/distribute-markers.log" ]]; then
      echo "  Wrote ${LOCAL_DIR}/distribute-launcher.log ($(wc -l < "${LOCAL_DIR}/distribute-launcher.log") lines)"
      echo "  Wrote ${LOCAL_DIR}/distribute-markers.log ($(wc -l < "${LOCAL_DIR}/distribute-markers.log") rank-0 events)"
    else
      echo "  NOTE: no rank-0 markers captured (may indicate cached hostPath hit — no download/broadcast needed)."
    fi
  fi
}

deploy_chart() {
  echo ">>> Deploying helm chart with ${VALUES_FILE}..."

  run_cmd kubectl delete mpijobs --all -n "$NAMESPACE" 2>/dev/null || true
  run_cmd kubectl delete computedomain inferencex -n "$NAMESPACE" 2>/dev/null || true
  run_cmd kubectl delete resourceclaims --all -n "$NAMESPACE" 2>/dev/null || true

  echo ">>> Waiting 15s for cleanup..."
  $DRY_RUN || sleep 15

  local base_path="${HELM_DIR}/values-gb300-base.yaml"
  local values_path="${HELM_DIR}/${VALUES_FILE}"
  [[ -f "$base_path" ]]   || { echo "ERROR: Base values file not found: $base_path"; exit 1; }
  [[ -f "$values_path" ]] || { echo "ERROR: Recipe values file not found: $values_path"; exit 1; }

  if $DRY_RUN; then
    echo "[DRY RUN] helm template + kubectl apply with ${base_path} + ${values_path}"
  else
    helm template inferencex "$HELM_DIR" \
      --namespace "$NAMESPACE" \
      -f "$base_path" \
      -f "$values_path" \
      | kubectl apply -n "$NAMESPACE" -f -
  fi
}

wait_for_ready() {
  echo ">>> Waiting for pods to be ready..."
  local max_wait=900
  local elapsed=0

  while (( elapsed < max_wait )); do
    local total_pods not_running
    total_pods=$(kubectl get pods -n "$NAMESPACE" \
      -l 'app.kubernetes.io/component in (prefill-launcher,prefill-worker,decode-launcher,decode-worker)' \
      --no-headers 2>/dev/null | wc -l)
    not_running=$(kubectl get pods -n "$NAMESPACE" \
      -l 'app.kubernetes.io/component in (prefill-launcher,prefill-worker,decode-launcher,decode-worker)' \
      --no-headers 2>/dev/null | awk '$3 != "Running" {c++} END {print c+0}')

    if (( total_pods > 0 )) && (( not_running == 0 )); then
      echo "  All ${total_pods} worker pods Running."
      break
    fi
    echo "  Waiting... (${elapsed}s, ${not_running}/${total_pods} pods not Running)"
    sleep 30
    elapsed=$((elapsed + 30))
  done

  if (( elapsed >= max_wait )); then
    echo "ERROR: Pods not ready after ${max_wait}s"
    kubectl get pods -n "$NAMESPACE" --no-headers
    exit 1
  fi

  # Helpers re-resolve the frontend pod each call because we may rollout-restart
  # it below if the discovery watcher is wedged (see auto-recovery block).
  resolve_frontend_pod() {
    kubectl get pods -n "$NAMESPACE" \
      -l app.kubernetes.io/component=frontend \
      --field-selector=status.phase=Running \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
  }
  fe_json_len() {
    local fe="$1" path="$2" key="$3"
    local body
    body=$(kubectl exec -n "$NAMESPACE" "$fe" -- \
      curl -sf --max-time 5 "http://localhost:8000${path}" 2>/dev/null || true)
    [[ -n "$body" ]] || { echo 0; return; }
    python3 -c "import sys,json
try:
  print(len(json.loads(sys.argv[1]).get('$key',[])))
except Exception:
  print(0)" "$body" 2>/dev/null || echo 0
  }
  fe_models_count()    { fe_json_len "$1" /v1/models data; }
  fe_health_endpoints() { fe_json_len "$1" /health endpoints; }

  echo ">>> Waiting for frontend /v1/models to populate..."
  # Canonical readiness signal (per dynamo source, lib/llm/src/discovery/watcher.rs):
  #   1. /v1/models contains at least one model id  (model registered with
  #      frontend's ModelManager via etcd watch)
  #   2. A streamed completion succeeds              (full disagg path active)
  #
  # Known failure mode: if the frontend lost its etcd/NATS connection during
  # startup (e.g. NATS DNS race when ConfigMap+pods come up together), the
  # discovery watcher silently wedges. /health continues to enumerate endpoint
  # instances directly from etcd (looks fine), but ModelManager never gets
  # populated, so /v1/models stays empty forever. The only fix in this dynamo
  # version is to restart the frontend pod — there is no admin reconcile RPC.
  # We auto-detect and recover from this once.
  local frontend_pod
  frontend_pod=$(resolve_frontend_pod)
  [[ -n "$frontend_pod" ]] || { echo "ERROR: no Running frontend pod found"; exit 1; }
  echo "  Frontend pod: ${frontend_pod}"

  local models_wait=0 models=0 endpoints=0 restarted=false
  while (( models_wait < 1800 )); do
    models=$(fe_models_count "$frontend_pod")
    if [[ "$models" =~ ^[0-9]+$ ]] && (( models > 0 )); then
      echo "  /v1/models populated (${models} model(s))."
      log_event "MODELS_POPULATED"
      break
    fi

    # After 10 min: if /health shows backends but /v1/models is empty, the
    # watcher is wedged. Restart frontend once and re-resolve the pod.
    if (( models_wait >= 600 )) && ! $restarted; then
      endpoints=$(fe_health_endpoints "$frontend_pod")
      if [[ "$endpoints" =~ ^[0-9]+$ ]] && (( endpoints > 0 )); then
        echo "  WEDGE DETECTED: /health shows ${endpoints} endpoint(s) but /v1/models is empty after 600s."
        echo "  Auto-recovery: restarting frontend deployment..."
        log_event "FRONTEND_AUTO_RESTART"
        kubectl -n "$NAMESPACE" rollout restart deployment/inferencex-frontend >/dev/null
        kubectl -n "$NAMESPACE" rollout status deployment/inferencex-frontend --timeout=180s >/dev/null
        sleep 10
        frontend_pod=$(resolve_frontend_pod)
        [[ -n "$frontend_pod" ]] || { echo "ERROR: frontend pod missing after restart"; exit 1; }
        echo "  New frontend pod: ${frontend_pod}"
        restarted=true
        # Reset the wait clock so the new pod gets a fresh 1800s budget. No more
        # auto-restart attempts after this one to avoid loops.
        models_wait=0
        continue
      fi
    fi
    sleep 15
    models_wait=$((models_wait + 15))
  done
  if (( models_wait >= 1800 )); then
    echo "ERROR: /v1/models still empty after recovery. Aborting."
    exit 1
  fi

  echo ">>> Waiting for prefill router activation in frontend logs..."
  # Activation log line is emitted from lib/llm/src/kv_router/prefill_router/activation.rs.
  # Required so requests use the disaggregated path; without it requests fall
  # back to decode-only and fail with "Disaggregated params are required for
  # decode mode".
  local pr_wait=0
  while (( pr_wait < 600 )); do
    if kubectl logs -n "$NAMESPACE" "$frontend_pod" 2>/dev/null \
        | grep -q 'Prefill router activated successfully'; then
      echo "  Prefill router activated."
      log_event "PREFILL_ROUTER_ACTIVATED"
      break
    fi
    sleep 10
    pr_wait=$((pr_wait + 10))
  done
  if (( pr_wait >= 600 )); then
    echo "WARNING: prefill router activation not seen after 600s. Probes will reveal if disagg is broken."
  fi

  echo ">>> Probing /v1/completions (3 consecutive successes required)..."
  local probe_wait=0 consecutive=0
  while (( probe_wait < 600 )); do
    local probe_ok
    probe_ok=$(kubectl exec -n "$NAMESPACE" "$frontend_pod" -- bash -c "
      curl -sS --max-time 30 -X POST http://localhost:8000/v1/completions \
        -H 'Content-Type: application/json' \
        -d '{\"model\":\"${MODEL_NAME}\",\"prompt\":\"ok\",\"max_tokens\":1,\"stream\":true}' 2>&1 \
      | grep -c '^data:' || true" 2>/dev/null || echo "0")
    if [[ "$probe_ok" =~ ^[0-9]+$ ]] && (( probe_ok >= 2 )); then
      consecutive=$((consecutive + 1))
      echo "  Probe OK ($consecutive/3)"
      if (( consecutive >= 3 )); then
        echo "  Inference probe passed — model is serving cleanly."
        log_event "READY"
        return
      fi
    else
      consecutive=0
      echo "  Probe failed (got $probe_ok data chunks) — waiting..."
    fi
    sleep 10
    probe_wait=$((probe_wait + 10))
  done
  echo "ERROR: /v1/completions probe did not reach 3 consecutive successes in 600s. Aborting."
  exit 1
}

copy_sa_bench() {
  local frontend_pod="$1"
  echo ">>> Copying sa-bench to ${frontend_pod}:/tmp/sa-bench/..."

  if $DRY_RUN; then
    echo "[DRY RUN] kubectl cp sa-bench/{bench.sh,benchmark_serving.py,backend_request_func.py,benchmark_utils.py}"
    return
  fi

  kubectl exec -n "$NAMESPACE" "$frontend_pod" -- mkdir -p /tmp/sa-bench /tmp/results
  for f in bench.sh benchmark_serving.py backend_request_func.py benchmark_utils.py; do
    kubectl cp "${SA_BENCH_DIR}/${f}" "${NAMESPACE}/${frontend_pod}:/tmp/sa-bench/${f}"
  done
  kubectl exec -n "$NAMESPACE" "$frontend_pod" -- chmod +x /tmp/sa-bench/bench.sh
}

ensure_tokenizer() {
  local frontend_pod="$1"
  echo ">>> Ensuring tokenizer is present at ${TOKENIZER_PATH}..."

  if $DRY_RUN; then
    echo "[DRY RUN] check/download tokenizer"
    return
  fi

  local have_tok
  have_tok=$(kubectl exec -n "$NAMESPACE" "$frontend_pod" -- \
    bash -c "[[ -f ${TOKENIZER_PATH}/tokenizer.json ]] && echo yes || echo no" 2>/dev/null || echo "no")
  if [[ "$have_tok" == "yes" ]]; then
    echo "  Tokenizer already present."
    return
  fi

  echo "  Downloading tokenizer (deepseek-ai/DeepSeek-R1-0528)..."
  kubectl exec -n "$NAMESPACE" "$frontend_pod" -- bash -c "
    mkdir -p ${TOKENIZER_PATH} && \
    python3 -c 'from huggingface_hub import snapshot_download; \
      snapshot_download(repo_id=\"deepseek-ai/DeepSeek-R1-0528\", \
        local_dir=\"${TOKENIZER_PATH}\", \
        allow_patterns=[\"tokenizer*\", \"*.json\", \"generation_config*\"])'
  "
}

run_benchmark() {
  local frontend_pod
  frontend_pod=$(kubectl get pods -n "$NAMESPACE" \
    -l app.kubernetes.io/component=frontend \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  [[ -n "$frontend_pod" ]] || { echo "ERROR: No frontend pod found"; exit 1; }

  copy_sa_bench "$frontend_pod"
  ensure_tokenizer "$frontend_pod"

  local result_dir="/tmp/results/sa-bench_isl_${ISL}_osl_${OSL}"
  local log_file="/tmp/results/${NAME}.log"
  local result_filename="results_concurrency_${CONC}_gpus_${TOTAL_GPUS}_ctx_${PREFILL_GPUS}_gen_${DECODE_GPUS}.json"
  local result_path="${result_dir}/${result_filename}"

  echo ">>> Running sa-bench (conc=${CONC}) on ${frontend_pod}..."
  echo "    Log:    ${log_file}"
  echo "    Result: ${result_path}"

  # sa-bench invocation — positional args match bench.sh contract.
  # ISL, OSL, single concurrency, inf request rate, tokenizer dir, model name,
  # is_disaggregated=true, total/prefill/decode GPU counts for the filename.
  local bench_cmd="bash /tmp/sa-bench/bench.sh \
    http://localhost:8000 \
    ${ISL} ${OSL} ${CONC} inf \
    ${TOKENIZER_PATH} ${MODEL_NAME} true \
    ${TOTAL_GPUS} ${PREFILL_GPUS} ${DECODE_GPUS}"

  if $DRY_RUN; then
    echo "[DRY RUN] kubectl exec ... -- nohup ${bench_cmd} > ${log_file} 2>&1 &"
    return
  fi

  # Launch in background — long benchmarks (conc=2253) can exceed kubectl exec timeouts.
  kubectl exec -n "$NAMESPACE" "$frontend_pod" -- \
    bash -c "nohup bash -c '${bench_cmd}' > ${log_file} 2>&1 &"

  echo ">>> Launched. Polling for completion..."

  local elapsed=0
  local max_poll=3600

  while (( elapsed < max_poll )); do
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))

    local json_exists
    json_exists=$(kubectl exec -n "$NAMESPACE" "$frontend_pod" -- \
      bash -c "[[ -f ${result_path} ]] && echo yes || echo no" 2>/dev/null || echo "no")

    if [[ "$json_exists" == "yes" ]]; then
      echo "  Benchmark complete (${elapsed}s elapsed)."
      break
    fi

    local progress
    progress=$(kubectl exec -n "$NAMESPACE" "$frontend_pod" -- \
      bash -c "tail -1 ${log_file} 2>/dev/null" 2>/dev/null || echo "waiting...")
    echo "  [${elapsed}s] ${progress}"
  done

  if (( elapsed >= max_poll )); then
    echo "ERROR: Benchmark did not complete within ${max_poll}s"
    echo "  Check log: kubectl exec -n $NAMESPACE $frontend_pod -- tail -80 $log_file"
    exit 1
  fi

  echo ""
  echo ">>> Extracting results..."

  local metrics
  metrics=$(kubectl exec -n "$NAMESPACE" "$frontend_pod" -- \
    cat "${result_path}" 2>/dev/null | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)
fields = [
    'total_token_throughput', 'output_throughput', 'request_throughput',
    'median_ttft_ms', 'p99_ttft_ms',
    'median_tpot_ms', 'p99_tpot_ms',
    'median_itl_ms', 'p99_itl_ms',
    'median_e2el_ms', 'p99_e2el_ms',
    'duration', 'completed', 'total_input_tokens', 'total_output_tokens',
]
print(','.join(str(d.get(f, 0)) for f in fields))
" 2>/dev/null || echo "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0")

  IFS=',' read -r TOTAL_TOK_S OUTPUT_TOK_S REQ_S \
                  MEDIAN_TTFT P99_TTFT \
                  MEDIAN_TPOT P99_TPOT \
                  MEDIAN_ITL P99_ITL \
                  MEDIAN_E2EL P99_E2EL \
                  DURATION COMPLETED TOT_IN TOT_OUT <<< "$metrics"

  local aks_per_gpu="0.0" pct_ix="0.0" status="UNKNOWN"
  if [[ "$TOTAL_TOK_S" != "0" ]]; then
    aks_per_gpu=$(python3 -c "print(f'{${TOTAL_TOK_S} / ${TOTAL_GPUS}:.1f}')")
    pct_ix=$(python3 -c "print(f'{(${TOTAL_TOK_S} / ${TOTAL_GPUS}) / ${IX_TOK_GPU} * 100:.1f}')")
    if python3 -c "exit(0 if 95.0 <= (${TOTAL_TOK_S} / ${TOTAL_GPUS}) / ${IX_TOK_GPU} * 100 <= 105.0 else 1)" 2>/dev/null; then
      status="PASS (within 5% of InferenceX)"
    else
      status="GAP (outside 5% of InferenceX)"
    fi
  fi

  echo "═══════════════════════════════════════════════════════════════"
  echo "  Results: ${NAME}"
  echo "═══════════════════════════════════════════════════════════════"

  if [[ "$TOTAL_TOK_S" != "0" ]]; then
    printf "  %-28s %s\n" "Total token throughput:" "${TOTAL_TOK_S} tok/s"
    printf "  %-28s %s\n" "Output token throughput:" "${OUTPUT_TOK_S} tok/s"
    printf "  %-28s %s\n" "Request throughput:" "${REQ_S} req/s"
    printf "  %-28s %s\n" "Median TTFT:" "${MEDIAN_TTFT} ms"
    printf "  %-28s %s\n" "Median TPOT:" "${MEDIAN_TPOT} ms"
    printf "  %-28s %s\n" "Per GPU:" "${aks_per_gpu} tok/s/GPU"
    printf "  %-28s %s\n" "InferenceX ref (${IX_DATE}):" "${IX_TOK_GPU} tok/s/GPU"
    printf "  %-28s %s%%\n" "% of InferenceX:" "${pct_ix}"
    printf "  %-28s %s\n" "Status:" "${status}"
  else
    echo "  Could not extract throughput from ${result_path}."
    echo "  Check log: kubectl exec -n $NAMESPACE $frontend_pod -- tail -80 $log_file"
  fi
  echo "═══════════════════════════════════════════════════════════════"

  copyback_results "$frontend_pod" "$result_path" "$log_file" \
    "$TOTAL_TOK_S" "$OUTPUT_TOK_S" "$REQ_S" \
    "$MEDIAN_TTFT" "$P99_TTFT" "$MEDIAN_TPOT" "$P99_TPOT" \
    "$MEDIAN_ITL" "$P99_ITL" "$MEDIAN_E2EL" "$P99_E2EL" \
    "$DURATION" "$COMPLETED" "$TOT_IN" "$TOT_OUT" \
    "$aks_per_gpu" "$pct_ix" "$status"
}

copyback_results() {
  local frontend_pod="$1"
  local pod_result_path="$2"
  local pod_log_path="$3"
  local total_tok="$4" out_tok="$5" req_s="$6"
  local med_ttft="$7" p99_ttft="$8"
  local med_tpot="$9" p99_tpot="${10}"
  local med_itl="${11}" p99_itl="${12}"
  local med_e2el="${13}" p99_e2el="${14}"
  local duration="${15}" completed="${16}" tot_in="${17}" tot_out="${18}"
  local per_gpu="${19}" pct_ix="${20}" status="${21}"

  if $DRY_RUN; then
    echo "[DRY RUN] would copy results to ${LOCAL_DIR:-${RESULTS_DIR}/${NAME}_${TIMESTAMP}}/"
    return
  fi

  local local_dir="${LOCAL_DIR:-${RESULTS_DIR}/${NAME}_${TIMESTAMP}}"
  mkdir -p "$local_dir"

  echo ">>> Copying results to ${local_dir}/ ..."

  kubectl cp "${NAMESPACE}/${frontend_pod}:${pod_result_path}" \
    "${local_dir}/result.json" 2>/dev/null || \
    echo "  WARNING: could not copy result.json (${pod_result_path})"

  kubectl cp "${NAMESPACE}/${frontend_pod}:${pod_log_path}" \
    "${local_dir}/run.log" 2>/dev/null || \
    echo "  WARNING: could not copy run.log (${pod_log_path})"

  cat > "${local_dir}/summary.txt" <<EOF
InferenceX AKS Benchmark Summary
═══════════════════════════════════════════════════════════════
Test:            ${NAME}
Timestamp (UTC): ${TIMESTAMP}
Recipe:          ${RECIPE}
SKU/Precision:   ${SKU} / ${PRECISION} / ${SPEC_METHOD}
Helm values:     ${VALUES_FILE}
Namespace:       ${NAMESPACE}
Frontend pod:    ${frontend_pod}

Topology
  Total GPUs:           ${TOTAL_GPUS}
  Prefill GPUs/worker:  ${PREFILL_GPUS}
  Decode  GPUs/worker:  ${DECODE_GPUS}

Workload
  ISL / OSL:            ${ISL} / ${OSL}
  Concurrency:          ${CONC}
  Duration (s):         ${duration}
  Completed requests:   ${completed}
  Total input tokens:   ${tot_in}
  Total output tokens:  ${tot_out}

Throughput
  Total tok/s:          ${total_tok}
  Output tok/s:         ${out_tok}
  Request/s:            ${req_s}
  Per GPU (tok/s):      ${per_gpu}

Latency (ms)
  TTFT   median / p99:  ${med_ttft} / ${p99_ttft}
  TPOT   median / p99:  ${med_tpot} / ${p99_tpot}
  ITL    median / p99:  ${med_itl} / ${p99_itl}
  E2EL   median / p99:  ${med_e2el} / ${p99_e2el}

InferenceX Comparison (official reference, date=${IX_DATE}, fetched=${IX_FETCHED})
  InferenceX tok/s/GPU: ${IX_TOK_GPU}
  InferenceX TPOT ms:   ${IX_MED_TPOT}  (ours: ${med_tpot})
  InferenceX TTFT ms:   ${IX_MED_TTFT}  (ours: ${med_ttft})
  AKS % of InferenceX:  ${pct_ix}%

Status:                 ${status}

Source paths (on frontend pod)
  Result JSON:  ${pod_result_path}
  Run log:      ${pod_log_path}

Artifacts in this directory
  result.json             — raw sa-bench output
  run.log                 — benchmark stdout/stderr from the frontend pod
  summary.txt             — this file
  timings.txt             — UTC event log (RUN_START, DEPLOY_*, DISTRIBUTE_*, WORKERS_READY, BENCH_*)
  pod-placement.tsv       — pod / role / node / gpu_indices / start_time at benchmark time
  distribute-launcher.log — full kubectl --timestamps log of the model-distribute launcher pod
  distribute-markers.log  — grep of rank-0 download + broadcast events from the launcher log
EOF

  echo "  Wrote ${local_dir}/result.json"
  echo "  Wrote ${local_dir}/run.log"
  echo "  Wrote ${local_dir}/summary.txt"
}

teardown_chart() {
  echo ">>> Tearing down..."
  run_cmd kubectl delete mpijobs --all -n "$NAMESPACE" 2>/dev/null || true
  run_cmd kubectl delete computedomain inferencex -n "$NAMESPACE" 2>/dev/null || true
  run_cmd kubectl delete resourceclaims --all -n "$NAMESPACE" 2>/dev/null || true
}

LOCAL_DIR="${RESULTS_DIR}/${NAME}_${TIMESTAMP}"
mkdir -p "$LOCAL_DIR"
: > "${LOCAL_DIR}/timings.txt"
log_event "RUN_START" "name=${NAME} values=${VALUES_FILE} conc=${CONC}$($DRY_RUN && echo ' DRY_RUN=true' || true)"

if ! $SKIP_DEPLOY; then
  log_event "DEPLOY_START"
  deploy_chart
  log_event "DEPLOY_END"
  if ! $DRY_RUN; then
    wait_for_distribution
    log_event "WAIT_READY_START"
    wait_for_ready
    log_event "WORKERS_READY"
    record_pod_placement
  fi
else
  $DRY_RUN || record_pod_placement
fi

log_event "BENCH_START"
run_benchmark
log_event "BENCH_END"

if $TEARDOWN; then
  teardown_chart
  log_event "TEARDOWN_DONE"
fi

log_event "RUN_END"

if ! $SKIP_STATS && ! $DRY_RUN; then
  if curl -fsS --max-time 2 http://localhost:9090/-/healthy >/dev/null 2>&1; then
    echo ""
    echo ">>> Generating Prometheus stats + plots..."
    if python3 "${SCRIPT_DIR}/scripts/collect-prom-stats.py" \
       && python3 "${SCRIPT_DIR}/scripts/plot-prom-stats.py"; then
      echo ">>> Stats + plots updated. Index: ${RESULTS_DIR}/plots-index.md"
    else
      echo ">>> WARNING: stats/plots generation failed (benchmark itself succeeded)" >&2
    fi
  else
    echo ""
    echo ">>> Skipping stats: Prometheus not reachable at localhost:9090."
    echo "    To enable, run in another shell:"
    echo "      kubectl -n monitoring port-forward svc/kube-prometheus-kube-prome-prometheus 9090:9090 &"
    echo "    Then: python3 ${SCRIPT_DIR}/scripts/collect-prom-stats.py"
    echo "          python3 ${SCRIPT_DIR}/scripts/plot-prom-stats.py"
  fi
fi

echo ""
echo "Done. Artifacts: ${LOCAL_DIR}"
