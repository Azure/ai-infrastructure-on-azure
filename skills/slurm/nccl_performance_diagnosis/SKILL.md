---
name: nccl-performance-diagnosis
description: "Analyze NCCL bandwidth results, scope intra-rack vs inter-rack failures, and use bisection algorithm to isolate bad nodes. GPU vs network root cause analysis."
---

# NCCL Performance Diagnosis

How to analyze NCCL bandwidth results, identify what type of failure is occurring, and isolate the bad node(s).

> **Scripts**: This skill references test scripts from the [Azure/ai-infrastructure-on-azure](https://github.com/Azure/ai-infrastructure-on-azure) repo. Clone it and run from the repo root.

## Diagnosis Framework

When NCCL bandwidth is below the expected baseline, work through these levels:

1. **Is the problem intra-rack or inter-rack?**
2. **Is it one node or multiple nodes?**
3. **Is it a GPU issue or a network issue?**

## Step 1: Scope the Problem

### Intra-rack (MNNVL) test fails

If a per-rack NCCL test (using all nodes in one MNNVL domain) shows low bandwidth:

- The problem is within the NVLink/NVSwitch fabric in that rack.
- One bad node in the rack will drag down the entire collective.
- Proceed to **bisection** to find the bad node.

### Inter-rack (IB-only) test fails

If cross-rack NCCL tests show low bandwidth:

- The problem is in the InfiniBand fabric.
- Could be a bad IB link, switch port, or pkey issue on one or more nodes.
- Check IB links on all participating nodes (see `ib_link_validation` skill).
- Also compare per-rack results — if one rack is consistently the slow side, the problem is nodes in that rack.

### Single-node test (intra-node only)

If all inter-node tests are fine but a single node shows issues:

- Run a 2-node NCCL test with the suspect node + a known-good node.
- If that pair fails: the suspect is confirmed bad.
- If that pair passes: the issue may be environmental/transient.

## Step 2: Bisection Algorithm

Bisection isolates the bad node(s) from a failing group by repeatedly splitting and testing.

### Algorithm

1. **Start**: Take all N nodes in the failing group.
2. **Split**: Divide into two halves (group A, group B).
3. **Test both halves in parallel** (as separate NCCL test jobs).
4. **Analyze**:
   - **Both pass**: The problem only occurs when all nodes interact — rare, possibly a specific switch or routing issue. Try recombining to confirm.
   - **One passes, one fails**: The passing half is "known good." Recurse on the failing half.
   - **Both fail**: Multiple bad nodes, one in each half. Recurse on both.
5. **Terminate** when a group has 2–3 nodes.
6. **Individual isolation**: Test each suspect node paired with a **different** known-good node. The node in the failing pair is the bad one.
7. **Drain** confirmed bad node(s).
8. **Verify**: Run the original test with remaining good nodes. Confirm it passes.

### Parallel pair testing

When testing 2–3 suspects individually, pair each with a different known-good node and run all pairs as separate jobs simultaneously. This avoids serializing the final isolation step.

Example with 3 suspects (S1, S2, S3) and known-good nodes (G1, G2, G3):

```
Test 1: [S1, G1]   → FAIL → S1 is bad
Test 2: [S2, G2]   → PASS → S2 is good
Test 3: [S3, G3]   → FAIL → S3 is bad
```

**Important**: Use a different good node for each pair to avoid the good node being a bottleneck or correlating failures.

### Minimum group sizes for NCCL testing

- GB300 MNNVL test: Minimum 2 nodes (NVLink bisection within rack).
- H100 IB test: Minimum 2 nodes.
- For meaningful bandwidth, 4+ nodes is preferred.

## Step 3: Root Cause Analysis

Once the bad node is identified, determine whether the issue is GPU or network:

### GPU issue indicators

- GPU GEMM test also fails on this node → GPU compute problem.
- `nvidia-smi nvlink -s` shows inactive or degraded NVLink connections.
- `dmesg` shows XID errors.
- `dcgmi diag -r 1` fails.

### Network issue indicators

- GPU GEMM test passes (compute is fine) but NCCL fails → network path issue.
- `ibstat` shows a port down or in `Polling` state.
- IB error counters are elevated (see `ib_link_validation` skill).
- pkey is missing or wrong on one port.

### NVSwitch / MNNVL issue indicators (GB300)

- NCCL intra-rack test fails but inter-rack test is fine between other racks.
- `nvidia-smi -q` shows `ClusterUUID: 00000000-0000-0000-0000-000000000000` (NVLink fabric not initialized).
- FabricManager errors in `systemctl status nvidia-fabricmanager`.
- NVLink errors: `nvidia-smi nvlink -e`.

## Bandwidth Patterns and Interpretation

| Pattern                                           | Likely Cause                                                         |
| ------------------------------------------------- | -------------------------------------------------------------------- |
| busbw ~50 % of expected                           | One bad node in a 2-node test                                        |
| busbw ~0                                          | NCCL cannot communicate — IB link down or pkey issue                 |
| busbw normal at small sizes, drops at large sizes | Congestion or IB bandwidth limit                                     |
| busbw varies across runs (±20 %)                  | Transient issue — noisy neighbor, thermal throttle, or IB congestion |
| All racks fail                                    | Cluster-wide issue — check switch, SM, or subnet manager             |
| One rack fails, others pass                       | Rack-level issue — NVSwitch, TOR switch, or power                    |

## Quick-vs-Full Test Strategy

| Scenario                               | Test Approach                        |
| -------------------------------------- | ------------------------------------ |
| Initial validation of a new cluster    | Full sweep (1K–16G) on full rack     |
| Routine daily check                    | Quick check (16G, 10 iters) per rack |
| After node replacement                 | Quick check on affected rack         |
| Investigating a user-reported slow job | Quick check on the job's nodelist    |
| Bad rack found                         | Bisect within that rack              |

## Tools Reference

- NCCL test launcher: `infrastructure_validations/slurm/NCCL/nccl_test.sh`
- Per-SKU configs: `infrastructure_validations/slurm/NCCL/configs/`
- GPU GEMM test: `infrastructure_validations/slurm/gpu_test/gpu_test.slurm`
- IB validation commands: see `ib_link_validation` skill
- Baselines: see `sku_performance_baseline` skill
