#!/bin/bash
#SBATCH -p gpu
#SBATCH --ntasks-per-node=8
#SBATCH --cpus-per-task=12
#SBATCH --gpus-per-node=8
#SBATCH --exclusive
#SBATCH --output=job.%J.out

export OMPI_MCA_coll_hcoll_enable=0
export NCCL_IB_PCI_RELAXED_ORDERING=1
export CUDA_DEVICE_ORDER=PCI_BUS_ID
export NCCL_SOCKET_IFNAME=eth0
export NCCL_TOPO_FILE=/opt/microsoft/ndv5-topo.xml
export NCCL_DEBUG=WARN
export NCCL_MIN_NCHANNELS=32

export OMPI_MCA_coll_hcoll_enable=0 \
	CUDA_DEVICE_ORDER=PCI_BUS_ID \
	NCCL_SOCKET_IFNAME=eth0 \
	UCX_TLS=rc \
	UCX_NET_DEVICES=mlx5_ib0:1 \
	NCCL_IB_QPS_PER_CONNECTION=4 \
	NCCL_IGNORE_CPU_AFFINITY=1 \
	NCCL_P2P_NET_CHUNKSIZE=$((512 * 1024)) \
	NCCL_PXN_DISABLE=1 \
	NCCL_MIN_NCHANNELS=32 \
	SHARP_SMX_UCX_INTERFACE=mlx5_ib0:1 \
	SHARP_COLL_ENABLE_SAT=1 \
	SHARP_COLL_LOG_LEVEL=3 \
	SHARP_COLL_ENABLE_PCI_RELAXED_ORDERING=1 \
	NCCL_COLLNET_ENABLE=1

PIN_MASK='ffffff000000,ffffff000000,ffffff,ffffff,ffffff000000000000000000,ffffff000000000000000000,ffffff000000000000,ffffff000000000000'

module load mpi/hpcx

srun --mpi=pmix \
	--cpu-bind=mask_cpu:$PIN_MASK \
	--ntasks-per-node=8 \
	--cpus-per-task=12 \
	--gpus-per-node=8 \
	--mem=0 \
	/opt/nccl-tests/build/all_reduce_perf -b 1K -e 16G -f 2 -g 1 -c 0
