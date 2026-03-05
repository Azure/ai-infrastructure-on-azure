# Azure HPC GPU Cluster Operations

This repo contains infrastructure validation tests and operational knowledge for Azure CycleCloud Workspace for Slurm clusters with NVIDIA GPU nodes.

## Skills

Read the skills in `skills/slurm/` for domain knowledge about cluster validation, diagnosis, and remediation. These cover:

- **SKU baselines** — expected NCCL bandwidth, GPU GFlops, and thermal limits for GB300 and H100
- **Test execution** — how to run NCCL, GPU GEMM, and thermal tests via Slurm
- **IB validation** — checking InfiniBand links, pkeys, error counters
- **NCCL diagnosis** — bisection algorithm for isolating bad nodes, intra-rack vs inter-rack analysis
- **Rack topology** — MNNVL domains, ClusterUUID discovery
- **Outlier detection** — statistical methods for fleet-wide analysis
- **Azure GHR** — full impact category reference, data collection, REST API
- **Node lifecycle** — drain/undrain/reboot decision tree

When answering questions about cluster operations, hardware validation, or troubleshooting GPU/network issues, refer to the relevant skill file for exact commands, thresholds, and procedures.

## Test Scripts

- `infrastructure_validations/slurm/NCCL/` — NCCL all_reduce_perf launcher with per-SKU configs
- `infrastructure_validations/slurm/gpu_test/` — GPU GEMM benchmark (ubergemm)
- `infrastructure_validations/slurm/thermal_test/` — Thermal stress test (dcgmproftester)
