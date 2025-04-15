# InfiniBand Topology

This section describes how InfiniBand (IB) networks are structured in Azure ND-series clusters, and how users can discover, interpret, and optimize their IB topology for maximum performance.

## 1. InfiniBand in Azure Supercomputing

Each VM is connected via HDR or NDR InfiniBand NICs, typically one NIC per GPU pair:

- NDv4: 4× 200 Gbps HDR  
- NDv5: 4× 400 Gbps NDR  

The physical layout includes multiple layers of switches. Your topology may support SHARP (Scalable Hierarchical Aggregation and Reduction Protocol), which accelerates collective operations in NCCL.

## 2. SHARP vs Non-SHARP Topology

| Topology Type | Description |
|---------------|-------------|
| SHARP-enabled | Uses special switch hierarchy to offload collective ops; faster NCCL all-reduce |
| Non-SHARP     | Standard fat-tree or leaf-spine IB; performance relies more on node placement and job packing |

SHARP is available only in select regions and clusters. Ask your support team for confirmation.

## 3. Discovering Topology

Use these tools:

- `ibstat` and `ibstatus` – check link state  
- `ibdiagnet` – discover fabric topology  
- `perfquery` – monitor port performance  
- `infiniband-exporter` – Prometheus exporter for IB metrics  

You may also inspect `/sys/class/infiniband/*/ports/*/rate` and use `mlxconfig` for NIC-level information.

## 4. Generating ToRsets

ToRsets (Top-of-Rack groupings) help align job placement with physical locality for performance.

To generate a ToRset from NCCL tests:

```bash
git clone https://github.com/Azure/azhpc-utils
cd azhpc-utils/scripts
bash create_torset.sh -d <test-output-dir>
```

Feed NCCL test logs to the script; it will output JSON with recommended packing sets.

## 5. Job Packing Best Practices

- Use ToRset info to minimize cross-rack communication  
- Prefer filling whole racks before crossing to the next  
- When SHARP is enabled, try to keep all nodes in the same aggregation group  

---

Next: [Benchmarking](benchmarking.md)
