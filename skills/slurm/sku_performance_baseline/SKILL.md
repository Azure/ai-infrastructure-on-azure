---
name: sku-performance-baseline
description: "Expected NCCL busbw, GPU GFlops, thermal limits, IB port counts, and rack sizes for GB300 and H100 SKUs. Warn and GHR thresholds."
---

# SKU Performance Baseline

Expected performance values for Azure HPC GPU SKUs. Use these baselines to determine whether test results indicate healthy or degraded hardware.

## SKU Reference

### Standard_ND128isr_GB300_v6 (Grace Blackwell)

| Metric | Expected | Warn | GHR |
|--------|----------|------|-----|
| GPU count | 4 per node | — | < 4 |
| GPU GEMM (ubergemm, 60 s) | ~1,850 TFlops/GPU | < 1,785 TFlops (3.5 %) | < 1,720 TFlops (7 %) |
| NCCL all_reduce busbw (intra-rack, MNNVL, 16 G) | ~937 GB/s | < 800 GB/s | < 600 GB/s |
| NCCL all_reduce busbw (inter-rack, IB-only, 16 G) | ~200 GB/s | < 180 GB/s | < 150 GB/s |
| Thermal stress (dcgmproftester, target 1004) | All GPUs pass | — | Any GPU fail |
| IB ports | 4 × 400 Gb/s (ib0–ib3) | — | Any port down |
| NVLink domain | 18 nodes per MNNVL rack (ClusterUUID) | < 18 nodes in rack | — |

- **Rack size**: 18 nodes (72 GPUs per MNNVL domain).
- **NVLink**: Inter-node NVLink via NVSwitch / MNNVL within a rack.
- **Interconnect**: InfiniBand NDR 400 Gb/s across racks, IB SL=1.

### Standard_ND96isr_H100_v5 (Hopper)

| Metric | Expected | Warn | GHR |
|--------|----------|------|-----|
| GPU count | 8 per node | — | < 8 |
| GPU GEMM (ubergemm, 60 s) | ~769 GFlops/GPU | < 742 GFlops (3.5 %) | < 715 GFlops (7 %) |
| NCCL all_reduce busbw (full sweep, 16 G) | ~450 GB/s | < 400 GB/s | < 300 GB/s |
| Thermal stress (dcgmproftester, target 1004) | All GPUs pass | — | Any GPU fail |
| IB ports | 8 × 400 Gb/s (ib0–ib7) | — | Any port down |

- **Rack size**: No MNNVL; NVSwitch is intra-node only.
- **NVLink**: 8 GPUs connected via NVSwitch within a single node.
- **Interconnect**: InfiniBand NDR 400 Gb/s, SHARP / CollNet enabled.

## How to Use These Baselines

1. **Run the test** (GPU GEMM, NCCL, thermal) on the target nodes.
2. **Compare results** against the Expected column for the node's SKU.
3. **If below Warn**: Re-test to confirm. Check for transient issues (thermal throttling, noisy neighbors).
4. **If below GHR**: Drain the node and file an Azure Guest Health Report.

## Notes

- GEMM values are per-GPU. A single underperforming GPU flags the entire node.
- NCCL busbw depends on node count and message size. Baselines assume a full rack at 16 G message size.
- Thermal test is binary pass/fail — any GPU failure is grounds for GHR.
- Always test with enough nodes to be meaningful (≥ 2 for NCCL, full rack preferred for MNNVL).
