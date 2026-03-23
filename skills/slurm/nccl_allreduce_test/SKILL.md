---
name: nccl-allreduce-test
description: "Run NCCL all_reduce_perf bandwidth tests via Slurm, configure per-SKU environment variables (MNNVL, SHARP, GDR), and interpret busbw results."
---

# NCCL AllReduce Test

How to run NCCL all_reduce_perf bandwidth tests, configure environment variables per SKU, and interpret results.

> **Scripts**: This skill references test scripts from the [Azure/ai-infrastructure-on-azure](https://github.com/Azure/ai-infrastructure-on-azure) repo. Clone it and run from the repo root.

## Test Binary

```
/opt/nccl-tests/build/all_reduce_perf
```

This is the standard NCCL test binary from [nccl-tests](https://github.com/NVIDIA/nccl-tests). It measures collective bandwidth across GPUs and nodes.

## Running via the Launcher

The launcher script is at `infrastructure_validations/slurm/NCCL/nccl_test.sh`. It loads per-SKU configs and handles sbatch submission.

```bash
cd infrastructure_validations/slurm/NCCL

# Full sweep — GB300, 4 nodes
./nccl_test.sh --sku graceblackwell -N 4

# Full sweep — H100, 8 nodes
./nccl_test.sh --sku hopper -N 8 -w ccw-gpu-[1-8]

# Quick bandwidth check — large messages only, 10 iterations
./nccl_test.sh --sku graceblackwell --begin-size 16G --end-size 16G --iters 10 -N 18

# Auto-detect SKU from nodelist
./nccl_test.sh -N 4 -w ccw-gpu-[1-4]
```

### CLI options

| Option              | Default      | Description                               |
| ------------------- | ------------ | ----------------------------------------- |
| `--sku NAME`        | auto-detect  | Config name: `graceblackwell` or `hopper` |
| `--begin-size SIZE` | `1K`         | Start message size                        |
| `--end-size SIZE`   | `16G`        | End message size                          |
| `--iters N`         | nccl default | Iterations per message size               |
| `--check`           | off          | Enable data correctness validation        |

All other arguments pass through to sbatch (e.g., `-N 4`, `-w nodelist`).

## Per-SKU Environment Variables

### Grace Blackwell (GB300 / NDv6)

Config file: `configs/graceblackwell.conf`

Key settings:

- 4 GPUs per node, 4 tasks per node, 24 CPUs per task
- MNNVL enabled (`NCCL_MNNVL_ENABLE=1`, `NCCL_NVLS_ENABLE=1`)
- DMA-BUF for GPU-direct (`NCCL_DMABUF_ENABLE=1`)
- SHM disabled (`NCCL_SHM_DISABLE=1`) — NVLink is faster
- IB SL=1 (`NCCL_IB_SL=1`) — required for Azure NDR fabric
- GDR C2C enabled (`NCCL_NET_GDR_C2C=1`)
- RDMA-SHARP plugin library on LD_LIBRARY_PATH

### Hopper (H100 / NDv5)

Config file: `configs/hopper.conf`

Key settings:

- 8 GPUs per node, 8 tasks per node, 12 CPUs per task
- CPU affinity mask binding (complex hex mask per GPU)
- Topology file: `NCCL_TOPO_FILE=/opt/microsoft/ndv5-topo.xml`
- PXN disabled (`NCCL_PXN_DISABLE=1`)
- Min 32 channels (`NCCL_MIN_NCHANNELS=32`)
- SHARP / CollNet enabled (`NCCL_COLLNET_ENABLE=1`)
- UCX transport (`UCX_TLS=rc`)
- IB PCIe relaxed ordering enabled

## Output Format

```
#                                                              out-of-place                       in-place
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
           0             0     float     sum      -1     0.02    0.00    0.00      0     0.01    0.00    0.00      0
        1024           256     float     sum      -1    17.94    0.06    0.11      0    17.94    0.06    0.11      0
...
  17179869184    4294967296     float     sum      -1  18285.0  939.58  936.93      0  18292.6  939.19  936.54      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 487.265
```

### Key columns

- **busbw** (bus bandwidth, GB/s): The primary metric for evaluating collective performance. This accounts for the algorithm's data movement pattern.
- **algbw** (algorithm bandwidth, GB/s): Raw data rate. Always ≥ busbw.
- **#wrong**: Data corruption errors (should be 0).

### What to look at

1. **Peak busbw at 16 G message size**: This is the headline number. Compare against SKU baseline.
2. **Avg bus bandwidth**: Reported at the end of the run. This averages across all message sizes — small messages drag it down, so it's always lower than peak.
3. **#wrong column**: Any non-zero value indicates data corruption — serious hardware problem.

## Quick vs Full Sweep

| Mode           | Begin | End | Iters   | Duration   | Purpose                                                    |
| -------------- | ----- | --- | ------- | ---------- | ---------------------------------------------------------- |
| Quick check    | 16G   | 16G | 10      | ~2 min     | Validate peak bandwidth                                    |
| Full sweep     | 1K    | 16G | default | ~15-30 min | Profile across all sizes, detect small-message regressions |
| Bisection test | 8G    | 16G | 20      | ~5 min     | Balance speed and confidence during fault isolation        |

## Expected Results

See `sku_performance_baseline` skill for per-SKU busbw targets.

### GB300 intra-rack (MNNVL, 18 nodes)

- Peak busbw at 16 G: ~937 GB/s
- This tests NVLink/NVSwitch/MNNVL interconnect within the rack.

### GB300 inter-rack (IB-only, across racks)

- Peak busbw at 16 G: ~200 GB/s
- This tests InfiniBand interconnect between racks.

### H100 (8 nodes, full IB)

- Peak busbw at 16 G: ~450 GB/s

## Failure Indicators

| Observation                    | What It Means                                                        |
| ------------------------------ | -------------------------------------------------------------------- |
| busbw near zero                | NCCL could not establish communication — check IB links, pkeys       |
| busbw < 50 % of expected       | Likely a bad node dragging down the collective                       |
| #wrong > 0                     | Data corruption — hardware fault, file GHR immediately               |
| Job hangs (no output growth)   | NCCL initialization stuck — likely a downed IB link or pkey mismatch |
| "NCCL WARN" in output about IB | IB fabric issue — check ibstat on all nodes                          |
