# Azure HPC GPU Cluster Operations (Skill-First)

This repository is operated with a **skill-first workflow** for Azure CycleCloud Workspace for Slurm and AKS clusters with NVIDIA GPU nodes.

## Mandatory Behavior

For any cluster operations, validation, or troubleshooting request:

1. Use the local skill at `.copilot/skills/ai-infra/SKILL.md` first.
2. Read the index in that `SKILL.md` to identify which reference files in `.copilot/skills/ai-infra/references/` to load.
3. Execute commands and thresholds from the selected reference files only.
4. Do not provide generic HPC advice when a reference exists for that task.
5. If required inputs are missing (SKU, nodelist, cluster name, orchestrator, failing job details), ask for them explicitly.

If the user invokes the skill explicitly with `/ai-infra <request>`, treat that as an explicit invocation and follow the same workflow.

## Local Skill Layout

```
.copilot/skills/ai-infra/
  SKILL.md                              # router + index + cross-cutting rules
  references/
    sku_baselines.md
    rack_topology.md
    ib_validation.md
    nccl_test.md
    nccl_diagnosis.md
    gpu_validation.md
    thermal_test.md
    outlier_detection.md
    ghr.md                              # Azure Guest Health Reporting
    node_drain_and_replace.md
```

Canonical source (symlink target) is `skills/ai-infra/`.

## Response Contract

For operational responses, follow this structure:

1. Selected reference files
2. Ordered run plan
3. Exact commands
4. Pass/fail thresholds
5. Action decision (continue, isolate, drain, reboot, GHR with specific impact category)

## Test Script Paths

- `infrastructure_validations/slurm/NCCL/` — NCCL all_reduce_perf launcher with per-SKU configs
- `infrastructure_validations/slurm/gpu_test/` — GPU GEMM benchmark (ubergemm)
- `infrastructure_validations/slurm/thermal_test/` — Thermal stress test (dcgmproftester)
- `infrastructure_validations/aks/NCCL/` — NCCL on AKS
- `infrastructure_validations/aks/NHC/` — Node Health Check on AKS
- `infrastructure_validations/aks/fio/` — Storage I/O test on AKS
