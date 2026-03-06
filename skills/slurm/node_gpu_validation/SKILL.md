---
name: node-gpu-validation
description: "Test GPU compute performance using ubergemm GEMM benchmarks. Parse CSV output, identify underperforming GPUs, run fleet-wide analysis."
---

# Node GPU Validation

How to test GPU compute performance on individual nodes using NVIDIA's ubergemm GEMM benchmark.

> **Scripts**: This skill references test scripts from the [Azure/ai-infrastructure-on-azure](https://github.com/Azure/ai-infrastructure-on-azure) repo. Clone it and run from the repo root.

## What It Tests

ubergemm runs a sustained General Matrix Multiply workload on each GPU independently. The output is GFlops per GPU. A healthy GPU produces consistent results near the SKU baseline; a degraded GPU will show significantly lower throughput.

## Running the Test

### Slurm batch script

The self-contained script is at `infrastructure_validations/slurm/gpu_test/gpu_test.slurm`.

```bash
# Test 4 nodes, 4 GPUs each (GB300)
sbatch --gpus-per-node=4 -N 4 gpu_test.slurm

# Test 8 nodes, 8 GPUs each (H100)
sbatch --gpus-per-node=8 -N 8 gpu_test.slurm

# Target specific nodes
sbatch --gpus-per-node=4 -N 2 -w ccw-gpu-[1-2] gpu_test.slurm
```

The script runs ubergemm for 60 seconds per GPU, in parallel across all GPUs on each node via `srun --ntasks-per-node=$SLURM_GPUS_ON_NODE`.

### ubergemm binary location

```
/usr/libexec/datacenter-gpu-manager-4/plugins/cuda13/updated/ubergemm
```

This path is consistent across both GB300 and H100 Azure HPC images.

### Manual single-node test

```bash
# Run on GPU 0 for 60 seconds
CUDA_VISIBLE_DEVICES=0 /usr/libexec/datacenter-gpu-manager-4/plugins/cuda13/updated/ubergemm -t 60
```

## Output Format

The batch script produces CSV output:

```
hostname,gpu0,gpu1,gpu2,gpu3
ccw-gpu-1,1856202,1849317,1852441,1847956
ccw-gpu-2,1851000,1848200,1850100,1849500
```

Each value is GFlops for that GPU. The raw ubergemm output contains a line like:

```
GFlops:1.85620e+06 GFlops
```

The batch script parses this with `grep -oP 'GFlops:[0-9.e+]+'` and converts via awk.

## Interpreting Results

### Per-node analysis

1. Parse each row into `hostname` and per-GPU GFlops values.
2. Take the **minimum** GFlops across GPUs on that node — one bad GPU flags the node.
3. Compare against the SKU baseline (see `sku_performance_baseline` skill).

### Fleet analysis

1. Collect per-node minimum GFlops across all tested nodes.
2. Compute fleet mean and standard deviation.
3. Flag nodes where min GFlops < warn threshold (3.5 % below expected).
4. Flag nodes where min GFlops < GHR threshold (7 % below expected).
5. Sort worst-first for triage.

### Statistical outlier detection

When the fleet is large (> 10 nodes), also flag nodes more than 2 standard deviations below the mean. This catches nodes that are degraded relative to peers even if still above the absolute threshold.

## Common Failure Patterns

| Pattern | Likely Cause |
|---------|-------------|
| All GPUs on a node are equally low | Thermal throttling, power capping, or PCIe bandwidth issue |
| One GPU significantly lower than others | Degraded GPU — hardware fault |
| All nodes in a rack are low | Power or cooling issue at rack level |
| GFlops near zero or parse error | GPU not visible, driver crash, XID error in dmesg |

## What to Do with Results

- **All nodes pass**: Record baseline for future comparison.
- **Warn-level nodes**: Re-test to confirm. Check `nvidia-smi -q` for thermal throttling or ECC errors. Consider running DCGMI diagnostics (`dcgmi diag -r 3`).
- **GHR-level nodes**: Drain the node, file GHR with category `generic` (include per-GPU GFlops in description).
- **Zero / missing output**: Check if GPUs are visible (`nvidia-smi -L`), check dmesg for XID errors (`sudo dmesg | grep -i xid`).
