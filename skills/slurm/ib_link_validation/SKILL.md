---
name: ib-link-validation
description: "Check InfiniBand connectivity, port state, partition keys, and error counters on Azure HPC nodes. Covers operstate, ibstat, pkey verification, link flap detection, and soft fixes."
---

# InfiniBand Link Validation

How to check InfiniBand connectivity, port state, partition keys, and error counters on Azure HPC nodes.

## IB Interface Layout

### GB300 (Standard_ND128isr_GB300_v6)
- 4 IB ports: `ib0`, `ib1`, `ib2`, `ib3`
- 4 × 400 Gb/s (NDR)
- HCA devices: `mlx5_ib0` through `mlx5_ib3` (plus additional for management)

### H100 (Standard_ND96isr_H100_v5)
- 8 IB ports: `ib0` through `ib7`
- 8 × 400 Gb/s (NDR)
- HCA devices: `mlx5_ib0` through `mlx5_ib7`

## Quick Health Check

### 1. Linux network layer — operstate

```bash
for i in ib0 ib1 ib2 ib3; do
  echo "$i: $(cat /sys/class/net/$i/operstate 2>/dev/null || echo missing)"
done
```

Expected: all `up`. If any shows `down` or `missing`, the link is not functional.

### 2. healthagent check

```bash
sudo /usr/bin/health
```

Returns JSON. Look for IB interfaces in the output — `carrier=-1` means link down.

### 3. IB layer — ibstat

```bash
ibstat | grep -A5 "Port 1"
```

Key fields:
- `State: Active` — link is up and routed
- `Physical state: LinkUp` — physical layer is connected
- `Rate: 400` — NDR speed

Bad states: `State: Down`, `Physical state: Polling` (cable or switch issue).

### 4. IB device list

```bash
ibv_devinfo | grep -E "hca_id|port:|state|phys_state|rate"
```

## Partition Key (pkey) Validation

Pkeys control IB subnet membership. NCCL traffic requires a valid pkey.

```bash
# Show pkeys on all ports
for dev in $(ibv_devinfo -l 2>/dev/null | grep -v "^$" | grep -v "device" | awk '{print $1}'); do
  echo "=== $dev ==="
  cat /sys/class/infiniband/$dev/ports/1/pkeys/* 2>/dev/null | sort -u
done
```

Expected: at least one non-zero pkey (typically `0x8001` or similar full-member key). If only `0x0000` or `0x7fff`, the port is not properly joined to the subnet.

### Common pkey commands

```bash
# Check specific device
cat /sys/class/infiniband/mlx5_ib0/ports/1/pkeys/0

# Verify NCCL can see the right interface
ibv_devinfo -d mlx5_ib0 -v | grep pkey
```

## Error Counter Checks

IB error counters indicate link quality issues. High error rates cause retransmissions that degrade NCCL performance.

```bash
# Per-port error counters
perfquery -x  # extended counters on default port

# All ports, specific counters
for port in 1; do
  for dev in mlx5_ib0 mlx5_ib1 mlx5_ib2 mlx5_ib3; do
    echo "=== $dev port $port ==="
    perfquery -x -d $dev -P $port 2>/dev/null | grep -i "err\|discard\|drop"
  done
done
```

Key counters:
- `SymbolErrorCounter` — encoding errors (cable/transceiver issue)
- `LinkErrorRecoveryCounter` — link retrained (flapping)
- `LinkDownedCounter` — link went down
- `PortRcvErrors` — received malformed packets
- `PortXmitDiscards` — packets dropped on transmit

### Threshold guidance

| Counter | Normal | Investigate |
|---------|--------|-------------|
| SymbolErrorCounter | 0 | > 0 (cable issue) |
| LinkErrorRecoveryCounter | 0 | > 0 (flapping) |
| LinkDownedCounter | 0 | > 0 (link failure history) |
| PortRcvErrors | 0 | > 100 |
| PortXmitDiscards | 0–low | > 1000 (congestion or config) |

## Link Flap Detection

```bash
# Check link_flap sysfs counter (if available)
for i in ib0 ib1 ib2 ib3; do
  echo "$i flaps: $(cat /sys/class/net/$i/carrier_changes 2>/dev/null || echo N/A)"
done
```

High `carrier_changes` indicates an unstable link (bad cable, transceiver, or switch port).

## Soft Fix: Bring Interface Up

```bash
sudo ip link set ib0 up
sudo ip link set ib1 up
sudo ip link set ib2 up
sudo ip link set ib3 up
```

After bringing links up, restart healthagent and re-check:

```bash
sudo systemctl restart healthagent && sleep 5
sudo /usr/bin/health
```

If the interface stays down after `ip link set up`, the problem is at the physical layer (cable, switch, HCA). A reboot may help; if not, file GHR with category `ib_down`.

## dmesg Diagnostics

```bash
# IB / Mellanox errors
sudo dmesg | grep -i "ib\|infiniband\|mlx" | tail -20

# Look for specific failure modes
sudo dmesg | grep -i "link_state\|link down\|port_inactive"
```

## GHR Categories for IB Issues

| Issue | GHR Category |
|-------|-------------|
| Port down (carrier=-1, not recoverable by reboot) | `ib_down` |
| Port flapping (high carrier_changes / LinkErrorRecovery) | `ib_flapping` |
