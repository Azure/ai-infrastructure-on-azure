# Azure HPC GPU Cluster Operations (Skill-First)

This repository is operated with a **skill-first workflow** for Azure CycleCloud Workspace for Slurm clusters with NVIDIA GPU nodes.

## Mandatory Behavior

For any cluster operations, validation, or troubleshooting request:

1. Use local skills from `.copilot/skills/` first.
2. Start with `.copilot/skills/slurm_router/SKILL.md` to select the right skill set.
3. Execute commands and thresholds from the selected `SKILL.md` files.
4. Do not provide generic HPC advice when a skill exists for that task.
5. If required inputs are missing (SKU, nodelist, cluster name, failing job details), ask for them explicitly.

## Local Skills Directory

Primary skill source:

- `.copilot/skills/slurm_router/SKILL.md` (intent router)
- `.copilot/skills/sku_performance_baseline/SKILL.md`
- `.copilot/skills/node_gpu_validation/SKILL.md`
- `.copilot/skills/ib_link_validation/SKILL.md`
- `.copilot/skills/nccl_allreduce_test/SKILL.md`
- `.copilot/skills/thermal_stress_test/SKILL.md`
- `.copilot/skills/nccl_performance_diagnosis/SKILL.md`
- `.copilot/skills/cluster_outlier_detection/SKILL.md`
- `.copilot/skills/rack_topology/SKILL.md`
- `.copilot/skills/azure_node_health_report/SKILL.md`
- `.copilot/skills/node_drain_and_replace/SKILL.md`

Canonical source (symlink targets) is `skills/slurm/`.

## Response Contract

For operational responses, follow this structure:

1. Selected skills
2. Ordered run plan
3. Exact commands
4. Pass/fail thresholds
5. Action decision (continue, isolate, drain, reboot, GHR)

## Test Script Paths

- `infrastructure_validations/slurm/NCCL/` — NCCL all_reduce_perf launcher with per-SKU configs
- `infrastructure_validations/slurm/gpu_test/` — GPU GEMM benchmark (ubergemm)
- `infrastructure_validations/slurm/thermal_test/` — Thermal stress test (dcgmproftester)
