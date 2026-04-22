---
name: node-drain-and-replace
description: "Slurm node lifecycle management — drain, undrain, reboot, and file for replacement. Decision tree for when to drain vs reboot vs GHR."
---

# Node Drain and Replace

Slurm node lifecycle management: when and how to drain, undrain, reboot, and file for replacement.

## Slurm Node States

| State       | Meaning                                               |
| ----------- | ----------------------------------------------------- |
| `idle`      | Available for jobs                                    |
| `allocated` | Running a job                                         |
| `mixed`     | Some CPUs/GPUs allocated, some free                   |
| `drained`   | Administratively removed from scheduling; no new jobs |
| `draining`  | Drained but still running existing job(s)             |
| `down`      | Node is unreachable or failed healthcheck             |
| `down*`     | Node is down with a reason                            |

## Drain a Node

```bash
sudo scontrol update NodeName=ccw-gpu-5 State=DRAIN Reason="IB_port_down_20250115"
```

**Always include a dated reason.** Format: `<issue>_<YYYYMMDD>`. This creates an audit trail so you know why nodes were drained and when.

### Drain multiple nodes

```bash
sudo scontrol update NodeName=ccw-gpu-[5-8] State=DRAIN Reason="NCCL_low_mnnvl_20250115"
```

### Check drain reasons

```bash
sinfo -R
```

## Undrain a Node

Return a drained node to service:

```bash
sudo scontrol update NodeName=ccw-gpu-5 State=RESUME Reason="fixed_after_reboot"
```

**Critical**: Actually run this command. Just saying the node is undrained doesn't make it so.

### Verify it's back in service

```bash
sinfo -N -n ccw-gpu-5 -o "%N %T"
```

Should show `idle` (or `allocated` if a job grabbed it immediately).

## Decision Tree: What to Do with a Bad Node

```
Issue Detected
│
├─ FabricManager error / XID 79 / XID 95?
│   └─ YES → Drain → Collect metadata → File GHR (skip reboot)
│
├─ IB port down?
│   ├─ Try soft fix: sudo ip link set ibX up
│   ├─ If soft fix works → restart healthagent → verify → undrain
│   └─ If soft fix fails → reboot → check → if still down → Drain + GHR
│
├─ GPU performance degraded?
│   ├─ Re-test to confirm (not transient)
│   ├─ Check nvidia-smi -q for throttling, ECC errors
│   ├─ Run dcgmi diag -r 1 for quick validation
│   ├─ If persistent → reboot → re-test
│   └─ If still degraded after reboot → Drain + GHR
│
├─ NCCL bandwidth low (one rack)?
│   ├─ Bisect to find the bad node (see nccl_performance_diagnosis)
│   ├─ Drain the bad node
│   ├─ Investigate the bad node (GPU test, IB check, healthcheck)
│   └─ File GHR if issue persists after reboot
│
├─ Thermal test failure?
│   ├─ Reboot → re-test
│   └─ If still fails → Drain + GHR (category: gpu_throttling or dcgm_failure)
│
└─ Unknown / general issue?
    ├─ Run healthcheck: sudo /usr/bin/health
    ├─ Check dmesg for errors
    ├─ Reboot → re-check
    └─ If unresolved → Drain + GHR (category: HpcGenericFailure)
```

## Reboot Procedure

### 1. BEFORE rebooting — cache metadata

```bash
# On the target node, save physical hostname and resource ID
# See azure_node_health_report skill for commands
```

This is **critical** — if you reboot first and the node doesn't come back, you won't have the data needed for a GHR.

### 2. Reboot

```bash
# From scheduler, via SSH to the node
ssh ccw-gpu-5 'sudo reboot'
```

### 3. Wait for node to return

Poll until the node is reachable (typically 2–3 minutes):

```bash
# Simple poll loop
for i in $(seq 1 20); do
  ssh -o ConnectTimeout=5 ccw-gpu-5 uptime 2>/dev/null && break
  echo "Waiting... ($i)"
  sleep 15
done
```

### 4. Verify after reboot

```bash
# Check healthagent
ssh ccw-gpu-5 'sudo /usr/bin/health'

# Check IB interfaces directly (healthagent may have stale data)
ssh ccw-gpu-5 'for i in ib0 ib1 ib2 ib3; do echo "$i: $(cat /sys/class/net/$i/operstate 2>/dev/null || echo missing)"; done'

# Check GPUs
ssh ccw-gpu-5 'nvidia-smi -L'

# Check NVLink
ssh ccw-gpu-5 'nvidia-smi nvlink -s 2>&1 | head -20'
```

### 5. If healthagent shows stale data

Real commands show everything OK but healthagent still reports failure:

```bash
ssh ccw-gpu-5 'sudo systemctl restart healthagent && sleep 5 && sudo /usr/bin/health'
```

## After Azure Replaces the Node

When Azure processes a GHR and replaces/repairs the physical hardware:

1. The node will come back online (may take hours to days).
2. **Verify the replacement**:
   - Run GPU GEMM test on the node.
   - Run a 2-node NCCL test (pair with a known-good node).
   - Check IB links and pkeys.
   - Run healthcheck.
3. **If all checks pass**: Undrain the node.
4. **If checks fail**: File a new GHR — the replacement may also be faulty.

## Batch Operations

### Drain all nodes in a failing rack

After bisection identifies a rack-level issue:

```bash
# Get all nodes with a specific ClusterUUID
RACK_NODES="ccw-gpu-[1-18]"
sudo scontrol update NodeName=$RACK_NODES State=DRAIN Reason="rack_nvswitch_failure_20250115"
```

### Undrain all nodes after validation

```bash
sudo scontrol update NodeName=ccw-gpu-[1-18] State=RESUME Reason="validated_after_repair"
```

### List all drained nodes

```bash
sinfo -t drain,drained -N -o "%N %T %E"
```

### Count nodes by state

```bash
sinfo -p gpu -h -o "%T" | sort | uniq -c | sort -rn
```
