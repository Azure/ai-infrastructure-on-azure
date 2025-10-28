# Multi-node NCCL all_reduce test

## Table of Contents

1. [Launch with SLURM](#launch-with-slurm)
2. [Launch with mpirun](#launch-with-mpirun)

## Launch with SLURM

```bash
# Run NCCL all_reduce on a given set of nodes
sbatch -w ccw-gpu-[1-10] nccl_test.slurm
```

## Launch with mpirun

This takes a SLURM node list format to create a hostfile:

```bash
./nccl_test_mpirun.sh ccw-gpu-[1-10]
```
