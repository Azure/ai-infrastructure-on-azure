
# Benchmarking
 
This section describes how to benchmark your Azure supercomputing cluster to verify expected performance and identify potential bottlenecks. Benchmarks also serve as a pre-check for production readiness and support engagement.
 
## 1. Why Benchmark?
 
- Validate cluster configuration (e.g., topology, SHARP enablement)
- Establish performance baselines for future regressions
- Identify underperforming nodes or links
- Support escalation by demonstrating hardware-level anomalies
 
## 2. NCCL Benchmarks
 
NCCL is the standard collective communication library for multi-GPU workloads using NVLink and InfiniBand.
 
Clone and build the tests:
 
```bash
git clone https://github.com/NVIDIA/nccl-tests.git
cd nccl-tests
make MPI=1
```
 
Then run:
 
```bash
mpirun -np 8 -x NCCL_DEBUG=INFO -x LD_LIBRARY_PATH \
  ./build/all_reduce_perf -b 8 -e 1G -f 2 -g 1
```
 
Use the number of GPUs you have available, and ensure each rank maps to a separate GPU.
 
## 3. SHARP vs Non-SHARP Output
 
| Test Pattern      | SHARP-enabled (NDv4) | Non-SHARP         |
|-------------------|----------------------|-------------------|
| AllReduce 1GB     | ~180 GB/s            | ~120 GB/s         |
| AllReduce 256MB   | ~90–120 GB/s         | ~60–80 GB/s       |
 
Performance depends on node locality and job packing. Use ToRset information to diagnose.
 
## 4. Interpreting Results
 
- **Flat or low throughput** across sizes suggests topology misalignment or SHARP not engaged
- **One GPU consistently slower** can indicate a bad PCIe lane or thermal throttling
- **High variability** between runs = likely job placement issue
 
Plot and compare runs to a known-good benchmark from your team or Microsoft.
 
## 5. Additional Tests
 
- `ib_read_bw` / `ib_write_bw` – raw IB throughput per link
- `dcgmi dmon -e 1000` – GPU perf counters
- `nvidia-smi nvlink --status` – validate NVLink health
 
---
 
Next: [Telemetry & Observability](telemetry.md)