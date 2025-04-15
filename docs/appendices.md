# Appendices

This section contains reference material, scripts, and diagnostic guidance to support users operating GPU supercomputing clusters on Azure.

## A. Diagnostic Scripts

### Node Health Check (AzHPC)

The AzHPC validation toolkit includes a modular node health check script:

```bash
git clone https://github.com/Azure/azhpc-validation
cd azhpc-validation
bash scripts/run-validation.sh
```

Includes checks for:

- GPU enumeration and driver status
- ECC errors
- PCIe/NVLink/IB connectivity
- NCCL functionality
- Clock/thermal status

### NCCL Benchmark Scripts

Preconfigured NCCL benchmark wrappers can be found in the same repo or customized:

```bash
mpirun -np 8 -x NCCL_DEBUG=INFO -x LD_LIBRARY_PATH \
  ./build/all_reduce_perf -b 8 -e 1G -f 2 -g 1
```

## B. Common Issues and Signatures

| Symptom                          | Possible Cause                         | Tool                        |
|----------------------------------|----------------------------------------|-----------------------------|
| Missing GPU                     | GPU failure, driver issue              | `nvidia-smi`, NHC           |
| Low NCCL bandwidth              | SHARP off, job not packed              | `all_reduce_perf`, ToRset   |
| InfiniBand link down            | Cable/NIC/switch issue                 | `ibstat`, `perfquery`       |
| ECC error spike                 | Faulty GPU                             | `nvidia-smi -q`, DCGM       |
| PCIe bus errors                 | NUMA misalignment, system misconfig    | `lspci`, `dmesg`            |

## C. Reference Links

- [AzHPC GitHub](https://github.com/Azure/azhpc)
- [Moneo GitHub](https://github.com/Azure/moneo)
- [GHR API Docs](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/guest-health)
- [NVIDIA NCCL](https://developer.nvidia.com/nccl)

## D. Feedback & Contributions

This guide is open to customer feedback. If you notice outdated info or would like to contribute improvements, reach out to your Microsoft account team or submit a pull request if hosted on GitHub.

---

End of Guide.
