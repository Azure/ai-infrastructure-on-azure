---
name: rack-topology
description: "MNNVL domain discovery on Azure GB300 clusters. ClusterUUID lookup via nvidia-smi, expected rack sizes per SKU, FabricManager troubleshooting."
---

# Rack Topology

How MNNVL domains work on Azure GB300 clusters, how to discover rack membership, and expected rack structure per SKU.

> **Scripts**: This skill references test scripts from the [Azure/ai-infrastructure-on-azure](https://github.com/Azure/ai-infrastructure-on-azure) repo. Clone it and run from the repo root.

## What Is a Rack / MNNVL Domain?

On GB300 (NDv6) clusters, nodes within a physical rack are connected via NVSwitch/NVLink in an MNNVL (Multi-Node NVLink) domain. This gives intra-rack bandwidth of ~900+ GB/s for allreduce operations — far higher than the ~200 GB/s available over InfiniBand between racks.

Each MNNVL domain has a unique **ClusterUUID** reported by nvidia-smi. All nodes sharing the same ClusterUUID are in the same physical rack and can use NVLink for communication.

## Rack Structure by SKU

### GB300 (Standard_ND128isr_GB300_v6)

- **18 nodes per rack** (72 GPUs per MNNVL domain)
- 4 GPUs per node
- Nodes within a rack communicate via NVLink/NVSwitch/MNNVL
- Nodes across racks communicate via InfiniBand NDR 400 Gb/s
- ClusterUUID is a valid UUID (e.g., `a1b2c3d4-e5f6-7890-abcd-ef1234567890`)

### H100 (Standard_ND96isr_H100_v5)

- **No MNNVL** — NVSwitch is intra-node only (8 GPUs within one node)
- 8 GPUs per node
- All inter-node communication is via InfiniBand
- ClusterUUID may not be present or meaningful
- Rack topology is less relevant for NCCL testing (no intra-rack NVLink advantage)

## Discovering Rack Topology

### Single node query

```bash
nvidia-smi -q | grep ClusterUUID
```

Output:

```
    ClusterUUID                       : a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

### Fleet-wide discovery with parallel-ssh

```bash
# From the scheduler node
parallel-ssh -H "ccw-gpu-1 ccw-gpu-2 ccw-gpu-3 ..." -t 15 -i \
  "nvidia-smi -q 2>/dev/null | grep 'ClusterUUID' | head -1 | awk -F': ' '{print \$2}'"
```

Output:

```
[1] 14:23:45 [SUCCESS] ccw-gpu-1
a1b2c3d4-e5f6-7890-abcd-ef1234567890
[2] 14:23:45 [SUCCESS] ccw-gpu-2
a1b2c3d4-e5f6-7890-abcd-ef1234567890
[3] 14:23:46 [SUCCESS] ccw-gpu-19
b2c3d4e5-f6a7-8901-bcde-f12345678901
```

Group nodes by UUID to get rack membership.

### Programmatic discovery

Using Slurm hostlist expansion and parallel SSH:

```bash
# Get all nodes in the GPU partition
NODES=$(sinfo -p gpu -h -N -o '%N' | sort -u | tr '\n' ' ')

# Query ClusterUUID from all nodes
parallel-ssh -H "$NODES" -t 15 -i \
  "nvidia-smi -q 2>/dev/null | grep 'ClusterUUID' | head -1 | awk -F': ' '{print \$2}'"
```

### Handling edge cases

- **Drained/down nodes**: Skip them — they can't be queried. Clear any cached rack_id.
- **ClusterUUID = N/A or all zeros**: NVLink fabric not initialized. This is a hardware issue — file GHR with category `nvlink_down`.
- **Node missing from output**: SSH failed — node may be unresponsive.

## Validating Rack Size

After discovery, verify each rack has the expected number of nodes:

| SKU          | Expected Rack Size |
| ------------ | ------------------ |
| GB300 (NDv6) | 18 nodes           |

If a rack has fewer than expected nodes:

- Check if the missing nodes are drained/down (expected — they were filtered out).
- If nodes are in `idle` or `allocated` state but didn't return a ClusterUUID, investigate those nodes.

## Using Rack Topology for Testing

### Per-rack NCCL tests (MNNVL)

Test each rack independently to validate intra-rack NVLink bandwidth:

```bash
# For each rack, run NCCL test on its nodes
./nccl_test.sh --sku graceblackwell -N 18 -w ccw-gpu-[1-18]
```

Expected busbw: ~937 GB/s at 16 G message size.

### Inter-rack NCCL tests (IB-only)

Pick one node from each rack and test across racks:

```bash
# One node per rack, testing IB fabric
./nccl_test.sh --sku graceblackwell -N 4 -w ccw-gpu-1,ccw-gpu-19,ccw-gpu-37,ccw-gpu-55
```

Use IB-only NCCL settings (disable MNNVL) for pure IB measurement.

### Rack-aware training node selection

For training jobs, prefer allocating full racks (or multiples of racks) to maximize MNNVL utilization. Incomplete rack allocation wastes NVLink bandwidth and forces more traffic over IB.

## FabricManager

NVLink/MNNVL requires NVIDIA FabricManager to be running:

```bash
systemctl status nvidia-fabricmanager
```

Healthy output includes `Active: active (running)`.

Common FabricManager issues:

- **"training in progress"** with ClusterUUID all zeros → NVLink fabric failed to initialize. GHR category: `nvlink_down`.
- **"FabricManager not running"** → Service crashed or failed to start. Try `sudo systemctl restart nvidia-fabricmanager`. If it won't start, GHR.
- **DCGM NVSwitch errors** → `dcgmi discovery -l | grep -i nvswitch` to check NVSwitch visibility.
