---
name: ai-infra
description: "Azure HPC and AI infrastructure operations on CycleCloud Workspace for Slurm and AKS clusters with NVIDIA GB300/H100 GPUs. Use for: NCCL bandwidth tests, GPU validation, InfiniBand checks, thermal stress, rack topology (MNNVL), Azure Guest Health Reporting (aka GHR and used for reporting a node failure to Azure), draining and replacing bad nodes, outlier detection, and SKU performance baselines. Covers both Slurm and AKS execution paths."
---

# AI Infrastructure on Azure

Operational knowledge for Azure HPC GPU clusters running on CycleCloud Workspace for Slurm or AKS, with NVIDIA GB300 (NDv6) and H100 (NDv5) GPUs.

This single skill is the entry point for all cluster validation, diagnosis, and remediation questions. It contains a routing index that points to detailed reference files in `references/`. **Read the relevant reference files before giving commands** — do not invent thresholds or procedures.

## How to Use This Skill

1. **Classify the request** using the Intent Map below.
2. **Read the listed reference files** before answering.
3. **Use only commands and thresholds that appear in the reference files.** If the user's question can't be answered from the references, say so and ask for clarification.
4. **Ask for missing inputs** explicitly: SKU (`Standard_ND128isr_GB300_v6` or `Standard_ND96isr_H100_v5`), nodelist, cluster name, orchestrator (Slurm or AKS), failing job context.
5. **Respond using the Response Contract** at the bottom.

If the user invokes this skill with `/ai-infra <request>`, treat that as an explicit invocation and proceed with the same workflow.

## Reference File Index

All reference files live in `skills/ai-infra/references/`.

### Concepts and baselines (orchestrator-agnostic)

| File                   | Covers                                                                                                                                                                                  |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sku_baselines.md`     | Expected NCCL busbw, GPU GFlops, thermal limits, IB ports, rack sizes for GB300 and H100. Warn and GHR thresholds.                                                                      |
| `rack_topology.md`     | MNNVL domain discovery via `nvidia-smi`, ClusterUUID, expected rack sizes per SKU, FabricManager troubleshooting.                                                                       |
| `ib_validation.md`     | InfiniBand port state (`operstate`, `ibstat`), partition keys, error counters, link flap detection, soft fixes.                                                                         |
| `nccl_diagnosis.md`    | Bisection algorithm, intra-rack vs inter-rack scoping, GPU vs network root cause, bandwidth pattern interpretation.                                                                     |
| `outlier_detection.md` | Statistical methods (absolute threshold, z-score, MAD) for fleet-wide GPU and NCCL analysis.                                                                                            |
| `ghr.md`               | **Azure Guest Health Reporting (GHR)** — used for reporting a node failure to Azure. Covers full impact category reference, IMDS/KVP data collection, REST API format, insight polling. |

### Test execution (currently Slurm; AKS counterparts to be added)

| File                | Covers                                                                                                                                                                       |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `nccl_test.md`      | Run `all_reduce_perf` via the Slurm launcher. Per-SKU env vars (MNNVL/SHARP/GDR), output columns, quick vs full sweep. AKS path: see `infrastructure_validations/aks/NCCL/`. |
| `gpu_validation.md` | Run ubergemm GEMM benchmark via Slurm. Parse CSV output, identify underperforming GPUs.                                                                                      |
| `thermal_test.md`   | Run dcgmproftester thermal stress via Slurm. Interpret pass/fail, throttle reasons, DCGMI levels. AKS path: see `infrastructure_validations/aks/`.                           |

### Remediation

| File                        | Covers                                                                                                 |
| --------------------------- | ------------------------------------------------------------------------------------------------------ |
| `node_drain_and_replace.md` | Slurm `drain`/`undrain`/reboot, decision tree for drain vs reboot vs GHR, post-replacement validation. |

## Intent Map

### New cluster bring-up / full validation

Read: `sku_baselines.md`, `rack_topology.md`, `nccl_test.md`, `gpu_validation.md`, `thermal_test.md`

### Slow training or low multi-node throughput

Read: `nccl_diagnosis.md`, `sku_baselines.md`, `ib_validation.md`, `rack_topology.md` (when topology correlation is needed)

### NCCL failures or low all-reduce bandwidth

Read: `nccl_test.md`, `nccl_diagnosis.md`, `ib_validation.md`, `outlier_detection.md` (fleet-wide analysis)

### GPU underperformance on one or more nodes

Read: `gpu_validation.md`, `outlier_detection.md`, `sku_baselines.md`

### Thermal throttling or suspected cooling issues

Read: `thermal_test.md`, `sku_baselines.md`, `gpu_validation.md` (if thermal impact on GEMM is suspected)

### InfiniBand link / pkey / errors investigation

Read: `ib_validation.md`, `nccl_diagnosis.md`, `rack_topology.md` (when rack-locality matters)

### Identify degraded nodes across fleet

Read: `outlier_detection.md`, `sku_baselines.md`, plus `gpu_validation.md` and/or `nccl_test.md` depending on the metric source

### Node remediation / drain / replace / file GHR (Guest Health Report)

Triggers: "file a GHR", "guest health report", "report a bad node to Azure", "report a node failure to Azure", "open a hardware issue with Azure", "health impact category".

Read: `node_drain_and_replace.md`, `ghr.md`

## Cross-Cutting Rules

These apply to every operational answer:

1. **Always collect node metadata before rebooting or draining.** PhysicalHostName (Hyper-V KVP pool 3) and Resource ID (IMDS) are required for any GHR. If the node goes down, you lose access to them. See `ghr.md` for exact commands.
2. **Use exact thresholds from `sku_baselines.md`.** Do not invent warn/GHR cutoffs.
3. **Never suppress test failures** — non-zero `#wrong` in NCCL output, dcgmproftester non-zero exit, XID errors in dmesg are all hard signals.
4. **For NCCL bandwidth issues, scope before bisecting.** Determine intra-rack vs inter-rack from per-rack tests before isolating individual nodes.
5. **GHR impact category must match the symptom.** See the category reference table in `ghr.md`. Use `HpcGenericFailure` only when nothing else fits.
6. **Test scripts live in `infrastructure_validations/`** in this repo. The references describe how to run them and how to interpret output; the runnable artifacts are the scripts themselves.

## Test Script Paths

- `infrastructure_validations/slurm/NCCL/` — NCCL `all_reduce_perf` launcher with per-SKU configs
- `infrastructure_validations/slurm/gpu_test/` — GPU GEMM benchmark (ubergemm)
- `infrastructure_validations/slurm/thermal_test/` — Thermal stress test (dcgmproftester)
- `infrastructure_validations/slurm/NHC/` — Node Health Check
- `infrastructure_validations/aks/NCCL/` — NCCL on AKS (via MPI Operator)
- `infrastructure_validations/aks/NHC/` — Node Health Check on AKS
- `infrastructure_validations/aks/fio/` — Storage I/O test on AKS

## Response Contract

For operational responses, follow this structure:

1. **Selected references** — list the reference files you used.
2. **Run plan** — concise ordered steps.
3. **Exact commands** — copied from the reference files.
4. **Pass/fail thresholds** — from `sku_baselines.md` or the relevant test reference.
5. **Action decision** — continue, isolate, drain, reboot, or file GHR with the specific impact category.
