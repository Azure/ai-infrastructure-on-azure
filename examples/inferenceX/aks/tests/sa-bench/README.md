# sa-bench — InferenceX/SemiAnalysis Benchmark Client

Benchmark client used to measure InferenceX serving throughput against the Dynamo
frontend. This is the same tool used to produce the official InferenceX reference
numbers, so AKS results using it are directly comparable to the InferenceX
reference (see `aks/tests/fetch-references.sh`).

## Source

Copied verbatim from the `srt-slurm` repository (the upstream benchmark client
is vendored here because it contains Dynamo SSE-aware handlers that the
TRT-LLM-bundled benchmark_serving.py lacks):

- **Repo**: https://github.com/ishandhanani/srt-slurm
- **Branch**: `sa-submission-q1-2026`
- **Commit**: `adb62456f7aaf3fbd7c82f7223b06221e9bd89e0`
- **Path**: `srtctl-benchmarks/sa-bench/`

The only local modification is `bench.sh` — we replaced the hardcoded
`MODEL_PATH="/model/"` override (line 26) with a pass-through from `$6` so the
tokenizer path can be supplied as an argument instead of requiring `/model/` to
exist in the frontend container.

## Why this and not TRT-LLM's bundled `benchmark_serving.py`?

The TRT-LLM-bundled `benchmark_serving.py` (at
`/opt/dynamo/venv/.../tensorrt_llm/serve/scripts/benchmark_serving.py` inside
the runtime container) cannot parse Dynamo's SSE streaming format — it chokes
on `event:` and `:` comment lines. The sa-bench fork has an
`async_request_dynamo_completions` function in `backend_request_func.py` that
handles these correctly.

Using sa-bench brought AKS results from ~70% of the InferenceX reference
(misleading, caused by the parser eating the first token's stream) to
**95–109% of InferenceX** across all 8 recipes.

## Files

| File | Purpose |
|---|---|
| `bench.sh` | Shell wrapper: warmup run at 250 RPS + main run at `inf`. Drives `benchmark_serving.py`. |
| `benchmark_serving.py` | Async benchmark client. 1301 lines. Supports `--backend dynamo`. |
| `backend_request_func.py` | Per-backend request handlers. Contains `async_request_dynamo_completions` (SSE-aware). |
| `benchmark_utils.py` | Shared helpers (dataset generation, percentile math). |
| `soak-loop.sh` | Long-duration soak wrapper: loops `benchmark_serving.py` iterations until `DURATION_SECS` elapses. Used for the 1-hour stability test. |

## Usage on AKS

The repo wrapper `../run-test.sh` takes care of:
1. kubectl-cp'ing these files onto the frontend pod at `/tmp/sa-bench/`
2. Running `bench.sh` with the correct args derived from a `conc-*.yaml` config
3. Pulling results back and comparing to the InferenceX reference

Manual invocation (inside the frontend pod):

```bash
bash /tmp/sa-bench/bench.sh \
  http://localhost:8000 \
  8192 1024 \
  24 \
  inf \
  /tmp/tokenizer/ \
  deepseek-r1-0528-fp4-v2 \
  true 34 2 32
```

Arguments (positional):
1. `ENDPOINT` — Dynamo frontend URL
2. `ISL` — input sequence length
3. `OSL` — output sequence length
4. `CONCURRENCIES` — one or more concurrencies separated by `x` (e.g. `24` or `5x12x24`)
5. `REQ_RATE` — request rate (usually `inf`; warmup always uses 250)
6. `MODEL_PATH` — tokenizer directory (NOT the full weights dir)
7. `MODEL_NAME` — served model name registered with Dynamo
8. `IS_DISAGGREGATED` — `true` for InferenceX (prefill + decode pools)
9. `TOTAL_GPUS` — total GPUs in deployment
10. `PREFILL_GPUS` — GPUs per prefill worker
11. `DECODE_GPUS` — GPUs per decode worker

Output: `/tmp/results/sa-bench_isl_<ISL>_osl_<OSL>/results_concurrency_<C>_gpus_<N>_ctx_<P>_gen_<D>.json`
