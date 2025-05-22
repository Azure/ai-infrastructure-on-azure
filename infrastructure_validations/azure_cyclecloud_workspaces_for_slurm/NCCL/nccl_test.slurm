#!/bin/bash
#SBATCH -p gpu
#SBATCH -t 1-0
#SBATCH --ntasks-per-node=8
#SBATCH --exclusive
#SBATCH --gpus-per-node=8
#SBATCH --mem=0
#SBATCH --output=job.%J.out

module load mpi/hpcx

export SCALE=$SLURM_NNODES
export DEVICES=8
export HOSTFILE="./hostfile"

# Generate hostfile from SLURM_NODELIST
scontrol show hostnames $SLURM_NODELIST >$HOSTFILE

sharp_args="-x NCCL_COLLNET_ENABLE=1 \
-x NCCL_ALGO=CollnetChain,NVLS \
-x SHARP_COLL_ENABLE_SAT=1 \
-x SHARP_COLL_LOG_LEVEL=3 \
-x SHARP_COLL_ENABLE_PCI_RELAXED_ORDERING=1
-x SHARP_SMX_UCX_INTERFACE=mlx5_ib0:1"

mpirun -np $((SCALE * DEVICES)) \
	--map-by ppr:8:node \
	-hostfile ./hostfile \
	-mca plm_rsh_no_tree_spawn 1 \
	-mca plm_rsh_num_concurrent 800 \
	-mca coll_hcoll_enable 0 \
	-x LD_LIBRARY_PATH \
	-x CUDA_DEVICE_ORDER=PCI_BUS_ID \
	-x UCX_TLS=rc \
	-x UCX_NET_DEVICES=mlx5_ib0:1 \
	-x NCCL_SOCKET_IFNAME=eth0 \
	-x NCCL_DEBUG=WARN \
	-x NCCL_MIN_NCHANNELS=32 \
	-x NCCL_IB_QPS_PER_CONNECTION=4 \
	-x NCCL_P2P_NET_CHUNKSIZE=$((512 * 1024)) \
	-x NCCL_PXN_DISABLE=1 \
	-x NCCL_TOPO_FILE=/opt/microsoft/ndv5-topo.xml \
	-x NCCL_IGNORE_CPU_AFFINITY=1 \
	/opt/nccl-tests/build/all_reduce_perf -i 0 -g 1 -t 1 -b 8G -e 8G -f 0 -R 1
