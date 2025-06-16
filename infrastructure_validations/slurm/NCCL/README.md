# Multi-node NCCL all_reduce test

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
