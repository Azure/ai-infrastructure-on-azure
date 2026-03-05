# Per-node GPU GEMM (ubergemm) test

Runs `ubergemm` on every GPU across all allocated nodes in parallel, reports
per-GPU GFlops as CSV output.

## Files

```
gpu_test/
  gpu_test.slurm   # Self-contained batch script
```

## Usage

Pass `--gpus-per-node` on the `sbatch` command line:

```bash
# GB300 (4 GPUs per node)
sbatch --gpus-per-node=4 -N 4 gpu_test.slurm

# H100 (8 GPUs per node)
sbatch --gpus-per-node=8 -N 8 -w ccw-gpu-[1-8] gpu_test.slurm
```

## Output

CSV with a header row, one line per node:

```
hostname,gpu0_gflops,gpu1_gflops,gpu2_gflops,gpu3_gflops
ccw-gpu-9,1823766,1874870,1857083,1869878
ccw-gpu-10,1829186,1870636,1848129,1834644
```

GFlops values are averaged over the steady-state portion of the ubergemm run
(lines after the "starting...." tuning phase).
