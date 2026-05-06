# Azure HPC GPU Cluster Operations

This repo contains infrastructure validation tests and operational knowledge for Azure CycleCloud Workspace for Slurm and AKS clusters with NVIDIA GPU nodes.

## Skills

A single skill, **`skills/ai-infra/`**, contains all operational knowledge as a `SKILL.md` index plus reference files in `references/`. When answering questions about cluster operations, hardware validation, or troubleshooting GPU/network issues, read `skills/ai-infra/SKILL.md` first to find the relevant reference files, then read those.

The skill covers:

- **SKU baselines** (`references/sku_baselines.md`) — expected NCCL bandwidth, GPU GFlops, and thermal limits for GB300 and H100
- **NCCL test execution** (`references/nccl_test.md`) — how to run NCCL all-reduce tests via Slurm (and pointers to the AKS path)
- **GPU validation** (`references/gpu_validation.md`) — ubergemm GEMM benchmark
- **Thermal stress** (`references/thermal_test.md`) — dcgmproftester
- **InfiniBand validation** (`references/ib_validation.md`) — checking IB links, pkeys, error counters
- **NCCL diagnosis** (`references/nccl_diagnosis.md`) — bisection algorithm for isolating bad nodes, intra-rack vs inter-rack analysis
- **Rack topology** (`references/rack_topology.md`) — MNNVL domains, ClusterUUID discovery
- **Outlier detection** (`references/outlier_detection.md`) — statistical methods for fleet-wide analysis
- **Azure GHR** (`references/ghr.md`) — Guest Health Reporting: full impact category reference, data collection, REST API
- **Node lifecycle** (`references/node_drain_and_replace.md`) — Slurm drain/undrain/reboot decision tree

## Test Scripts

- `infrastructure_validations/slurm/NCCL/` — NCCL all_reduce_perf launcher with per-SKU configs
- `infrastructure_validations/slurm/gpu_test/` — GPU GEMM benchmark (ubergemm)
- `infrastructure_validations/slurm/thermal_test/` — Thermal stress test (dcgmproftester)
- `infrastructure_validations/aks/NCCL/` — NCCL test on AKS
- `infrastructure_validations/aks/NHC/` — Node Health Check on AKS
- `infrastructure_validations/aks/fio/` — Storage I/O test on AKS
