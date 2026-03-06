---
name: slurm_router
description: "Router for Azure HPC Slurm operations. Selects the correct skills for validation, NCCL diagnosis, IB checks, topology, outlier detection, thermal checks, and node replacement workflows. Use this skill first for any Slurm GPU cluster question."
---

# Slurm Skill Router

Use this skill first for any cluster-operations question in this repo.

## Goal

Map user intent to the correct skill(s), then execute only the procedures and thresholds from those selected skills.

## Required Workflow

1. Classify the request using the intent map below.
2. Explicitly list selected skills before giving commands.
3. Use exact commands, thresholds, and decision criteria from selected skill files.
4. If data is missing, ask for the minimum required input (SKU, nodelist, cluster name, failing job context).
5. Do not invent thresholds or procedures outside the selected skills.

## Intent Map

### New cluster bring-up / full validation
Use:
- `sku_performance_baseline`
- `rack_topology`
- `nccl_allreduce_test`
- `node_gpu_validation`
- `thermal_stress_test`

### Slow training or low multi-node throughput
Use:
- `nccl_performance_diagnosis`
- `sku_performance_baseline`
- `ib_link_validation`
- `rack_topology` (when topology correlation is needed)

### NCCL failures or low all-reduce bandwidth
Use:
- `nccl_allreduce_test`
- `nccl_performance_diagnosis`
- `ib_link_validation`
- `cluster_outlier_detection` (fleet-wide analysis)

### GPU underperformance on one or more nodes
Use:
- `node_gpu_validation`
- `cluster_outlier_detection`
- `sku_performance_baseline`

### Thermal throttling or suspected cooling issues
Use:
- `thermal_stress_test`
- `sku_performance_baseline`
- `node_gpu_validation` (if thermal impact on GEMM performance is suspected)

### InfiniBand link/pkey/errors investigation
Use:
- `ib_link_validation`
- `nccl_performance_diagnosis`
- `rack_topology` (when rack-locality matters)

### Identify degraded nodes across fleet
Use:
- `cluster_outlier_detection`
- `sku_performance_baseline`
- `node_gpu_validation` and/or `nccl_allreduce_test` (depending on metric source)

### Node remediation / drain / replace / GHR
Use:
- `node_drain_and_replace`
- `azure_node_health_report`

## Response Contract

For every operations answer:

1. **Selected skills:** list skill names.
2. **Run plan:** concise ordered steps.
3. **Commands:** exact commands from selected skills.
4. **Pass/fail criteria:** thresholds from selected skills.
5. **Decision:** next action (continue, drain, reboot, or file GHR).

## Skill Locations

- `skills/slurm/sku_performance_baseline/SKILL.md`
- `skills/slurm/node_gpu_validation/SKILL.md`
- `skills/slurm/ib_link_validation/SKILL.md`
- `skills/slurm/nccl_allreduce_test/SKILL.md`
- `skills/slurm/thermal_stress_test/SKILL.md`
- `skills/slurm/nccl_performance_diagnosis/SKILL.md`
- `skills/slurm/cluster_outlier_detection/SKILL.md`
- `skills/slurm/rack_topology/SKILL.md`
- `skills/slurm/azure_node_health_report/SKILL.md`
- `skills/slurm/node_drain_and_replace/SKILL.md`
