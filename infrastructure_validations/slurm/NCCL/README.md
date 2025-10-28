# Multi-node NCCL all_reduce test

## Table of Contents

1. [Launch with SLURM](#1-launch-with-slurm)
2. [Launch with mpirun](#2-launch-with-mpirun)

## 1. Launch with SLURM

```bash
# Run NCCL all_reduce on a given set of nodes
sbatch -w ccw-gpu-[1-10] nccl_test.slurm
```

## 2. Launch with mpirun

This takes a SLURM node list format to create a hostfile:

```bash
./nccl_test_mpirun.sh ccw-gpu-[1-10]
```
