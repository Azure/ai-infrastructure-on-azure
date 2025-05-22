# Node and cluster validations
Ensuring cluster readiness is essential prior to executing large-scale LLM training benchmarks. Our validation process on Azure involved several components, *i.e.* node health checks, NCCL all-reduce performance testing, and GPU thermal screening. This systematic approach enabled early detection of hardware or software inconsistencies and ensured consistent baseline performance. To get a more consistent test result, we recommend setting the persistent mode and locking the GPU frequency on all GPU nodes.

Example for NDv5 H100 GPU
```bash
sudo nvidia-smi -pm 1 
sudo nvidia-smi -lgc 1980 --mode 1
```

## Node Health Checks (NHC)
We used AzureHPC Node Health Checks (AzNHC) to validate node-level functionality. This solution builds on the well-established LBNL NHC framework and adds Azure-specific hardware validation for various HPC and AI VM SKUs, including the NDv5 H100-series used in this benchmark. AzNHC runs inside a Docker container and can be invoked directly via a wrapper script:
```bash
sudo /opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh
```
AzNHC provides targeted tests per SKU, including checks for GPU presence, NVLink integrity, ECC memory errors, GPU bandwidth (device-to-host/host-to-device), InfiniBand throughput (GDR and non-GDR), topology, and NCCL intra-node all-reduce performance. For our validation, we used a distributed Slurm job to execute health checks across all compute nodes.  

The firmware version check ensures consistent InfiniBand HCA firmware across nodes, which is critical for stable NCCL performance. Any failing nodes were drained and replaced prior to proceeding.

## NCCL all-reduce Validation
Following node-level validation, we verified inter-node GPU communication performance using NCCL all-reduce tests. The Azure HPC image includes a prebuilt version of the NCCL test suite under `/opt/nccl-tests/build/`. The all-reduce test was run at full scale using MPI, testing collective bandwidth across all GPUs:

We configured the NCCL environment for optimal collective performance, including CollNet/NVLS, GDR, and relaxed PCI ordering. If aggregate bandwidth deviated from expected baselines, we performed binary search and pairwise NCCL tests to isolate underperforming nodes. This method quickly identifies outliers that degrade collective performance.

## GPU Thermal Screening
Finally, to mitigate the risk of thermal throttling during extended training runs, we conducted GPU thermal screening using synthetic GEMM workloads. We used the `dcgmproftester12` tool to stress GPUs and monitored thermal behavior using `nvidia-smi`.

We verified that all GPUs remained below their thermal thresholds and no Throttle or TLimit events occurred. Any nodes failing thermal screening were marked as DRAIN in Slurm and replaced to maintain thermal headroom during full-scale training.
