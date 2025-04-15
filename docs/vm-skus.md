# VM SKU Reference

This section provides detailed specifications and usage guidance for Azure ND-series VM SKUs commonly used in supercomputing workloads.

## ND A100 v4 (NDv4)

**Hardware Specs:**

- 8× NVIDIA A100 80GB SXM GPUs (NVLink 600 GB/s GPU-GPU)
- Dual AMD EPYC 7V73X CPUs (96 cores total)
- 900 GB/s memory bandwidth per GPU
- 1.6 TB system RAM
- 4× 200 Gbps HDR InfiniBand NICs (Mellanox HCAs)
- 2× 1.9TB NVMe SSDs

**Topology:**

- Full NVLink mesh (each GPU connected to every other GPU)
- GPUs connected to CPUs via PCIe 4.0 switches
- 1 NIC per GPU pair (affects SHARP topology)

**Recommended Use:**

- Large-scale AI model training
- NCCL-based multi-GPU workloads
- SHARP-enabled collective comms (if supported by IB fabric)
- Tight coupling with Slurm / MPI

## ND H100 v5 (NDv5)

**Hardware Specs:**

- 8× NVIDIA H100 80GB SXM GPUs (NVLink 900 GB/s GPU-GPU)
- Dual Intel Sapphire Rapids CPUs (112 cores total)
- 1.8 TB system RAM
- 4× 400 Gbps NDR InfiniBand NICs
- 2× NVMe local drives

**Topology:**

- Full NVLink (NVSwitch)
- PCIe Gen5 root complex
- Each NIC is dedicated to a GPU pair (as in NDv4), but with 400 Gbps bandwidth

**Recommended Use:**

- GPT-style LLM training
- Transformer-heavy models with high flops/param density
- Better perf/Watt vs NDv4
- Use where NVLink bandwidth or PCIe bottlenecks were a constraint on NDv4

## SKU Selection Guidance

| Workload Type              | Suggested SKU |
|---------------------------|---------------|
| FP32 CNN Training         | NDv4          |
| FP16/BF16 LLM Training    | NDv5          |
| Multi-node NCCL (SHARP)   | NDv4 (if SHARP enabled) |
| Large batch inference     | NDv5          |
| Custom kernels or legacy CUDA apps | NDv4 or NDv5 depending on dependency set |

> **Note:** SHARP collectives require SHARP-compatible IB topology. Confirm with your support team.

## Availability

VM SKU availability may vary by Azure region. For production-scale deployments, confirm SKU capacity with your Azure account team.

---

Next: [Validation & Health Checks](validation.md)
