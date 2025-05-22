# Optimizing DGX Benchmark on Azure

Due to differences in virtualization, network fabric, and topology awareness, Azure demands tailored optimizations.

## System-Level Optimizations

The system-level optimization involves ensuring proper CPU, GPU, and NIC affinity using an NCCL topology file, which is included as part of the Azure HPC VM image. This file defines the mapping between NUMA nodes, GPUs, and network interfaces, allowing the NCCL library to assign communication threads to the correct CPU cores.

This file must be explicitly mounted into the container and passed to the job via the `NCCL_TOPO_FILE` environment variable. Additionally, setting `NCCL_IGNORE_CPU_AFFINITY=1` ensures that NCCL ignores MPI’s default CPU binding and relies solely on the topology file for affinity decisions.

This configuration is crucial for low-latency communication using NCCL’s LL (Low-Latency) protocol, which transfers small and medium messages via pinned CPU buffers. Without proper CPU-GPU affinity, inter-NUMA communication introduces significant performance degradation.

Further NCCL tuning on Azure includes the following recommended settings:

| Variable                     | Value                          | Description                                            |
| ---------------------------- | ------------------------------ | ------------------------------------------------------ |
| `NCCL_TOPO_FILE`             | `/opt/microsoft/ndv5-topo.xml` | Ensures NUMA-aware GPU/NIC/CPU mapping                 |
| `NCCL_P2P_NET_CHUNKSIZE`     | `2097152` (2MB)                | Increases P2P transfer granularity                     |
| `NCCL_MIN_CHANNELS`          | `32`                           | Improves throughput for collectives like ReduceScatter |
| `NCCL_IB_QPS_PER_CONNECTION` | `4`                            | Improves InfiniBand queue performance                  |
| `NCCL_PXN_DISABLE`           | `1`                            | Enables zero-copy design for NCCL P2P                  |
| `NCCL_IGNORE_CPU_AFFINITY`   | `1`                            | Ensures NCCL bindings override MPI-affinity            |

The Slurm `srun` command must also include `--cpu-bind=mask_cpu:"..."` to specify optimal per-rank CPU binding based on the topology file. A Slurm job submission example is shown below:

```bash
export NCCL_TOPO_FILE=/opt/microsoft/ndv5-topo.xml
export NCCL_P2P_NET_CHUNKSIZE=2097152

srun --container-image ${IMAGE} \
     --container-writable \
     --container-mounts ${NCCL_TOPO_FILE},${DATA_DIR}:/datasets/,${RESULT_DIR},$INDEX_MAPPING_DIR,${STAGE_PATH}/cfg:/cfg/ \
     --container-env=NCCL_TOPO_FILE,NCCL_P2P_NET_CHUNKSIZE \
     --cpu-bind=mask_cpu:"fff,fff000,fff000000,fff000000000,..." \
     --no-container-mount-home \
     <launcher-script>
```

## Model-Level Parameter Tuning

In addition to system configuration, optimizing the model parallelism parameters was essential for certain LLMs.

### NeMo Megatron 175B

Reducing `virtual_pipeline_model_parallel_size` from `12` to `2` significantly reduced the number of `ncclSendRecv` operations. This improved communication overlap with computation, reducing time spent in key CUDA kernels (`ncclSendRecv`, `kuserbuffers_pushrecv`, etc.) and leading to step time improvements.

### Llama 3.1 70B

Reducing `context_model_parallel_size` from `2` to `1` eliminated context-parallel all-gather operations. This reduced skew-induced delays in the downstream tensor-parallel reduce-scatter phase. Additionally, increasing the effective `data_parallel_size` enabled more efficient batch processing.
