---
name: cluster-outlier-detection
description: "Statistical methods for identifying underperforming nodes from batch test results. Absolute thresholds, z-score, and MAD methods for fleet-wide GPU and NCCL analysis."
---

# Cluster Outlier Detection

Statistical methods for identifying underperforming nodes from batch test results.

## When to Use

After running fleet-wide tests (GPU GEMM, NCCL per-rack, thermal), you have a set of per-node or per-rack metrics. Outlier detection finds nodes that are degraded relative to their peers, even if their absolute values are technically within tolerance.

## Method 1: Absolute Threshold

Compare each node's metric against a fixed threshold from the SKU baseline.

```
if metric < threshold:
    flag node
```

Pros: Simple, deterministic, directly actionable.
Cons: Misses nodes that are degrading but not yet below the threshold. Does not adapt to fleet conditions.

Use the thresholds from `sku_performance_baseline` for pass/fail decisions.

## Method 2: Z-Score (Standard Deviation)

Compute fleet mean and standard deviation, then flag nodes more than N standard deviations below the mean.

```
mean = average(all_node_metrics)
stdev = standard_deviation(all_node_metrics)
z_score = (node_metric - mean) / stdev

if z_score < -2.0:
    flag as outlier
```

### Threshold guidance

| Z-score | Percentile | Action |
|---------|-----------|--------|
| < -1.5 | ~7th percentile | Monitor — performance is below peers |
| < -2.0 | ~2nd percentile | Investigate — likely degraded |
| < -3.0 | ~0.1th percentile | Drain — almost certainly hardware issue |

Pros: Adapts to actual fleet performance. Catches relative degradation.
Cons: Requires enough data points (≥ 10 nodes). Sensitive to outliers in the dataset itself (one very bad node inflates stdev).

### Robust variant: use median and MAD

For small fleets or fleets with known bad nodes:

```
median = median(all_node_metrics)
MAD = median(|metric - median| for each node)
modified_z = 0.6745 * (node_metric - median) / MAD

if modified_z < -2.0:
    flag as outlier
```

MAD (Median Absolute Deviation) is less sensitive to extreme outliers than standard deviation.

## Method 3: Deviation from Expected

Compare each node against the expected value for the SKU, expressed as percentage deviation.

```
deviation_pct = (expected - node_metric) / expected * 100

if deviation_pct > warn_pct:
    flag as warning (e.g., > 3.5%)
if deviation_pct > ghr_pct:
    flag for GHR (e.g., > 7%)
```

This is what the GPU GEMM analysis uses (see `node_gpu_validation` skill).

## Applying to Different Test Types

### GPU GEMM results

- **Metric**: Minimum GFlops across GPUs on each node (one bad GPU = bad node).
- **Expected**: Per-SKU from `sku_performance_baseline`.
- **Method**: Absolute threshold (deviation from expected) **plus** z-score across fleet.
- **Granularity**: Per-GPU if you want to identify which GPU is degraded.

### NCCL per-rack results

- **Metric**: Peak busbw at 16 G message size for each rack's NCCL test.
- **Expected**: Per-SKU MNNVL or IB baseline.
- **Method**: Absolute threshold first. For racks near the threshold, compare against other racks' results.
- **Note**: A single bad node in a rack drags down the entire rack's result. If one rack fails, bisect it (see `nccl_performance_diagnosis`).

### NCCL pairwise results

- **Metric**: busbw for each node-pair test.
- **Expected**: Similar to full-rack baseline (may be slightly higher for 2-node test due to less contention).
- **Method**: The node that appears in all failing pairs is the bad one. If node A fails with [B, C, D] but B passes with [C, D], then A is the problem.

### Thermal test results

- **Metric**: Binary pass/fail per GPU.
- **Method**: No statistics needed — any failure is a flag.

## Reporting Format

When presenting outlier results, include:

1. **Fleet summary**: Total nodes, mean, stdev, min, max.
2. **Sorted list** (worst first): Node name, metric value, deviation from expected (%), z-score.
3. **Action categories**:
   - GHR required (below absolute GHR threshold)
   - Warning (below absolute warn threshold or z < -2)
   - Healthy (above all thresholds)
4. **Per-node detail**: If GPU GEMM, include per-GPU values for flagged nodes (to identify which GPU).
