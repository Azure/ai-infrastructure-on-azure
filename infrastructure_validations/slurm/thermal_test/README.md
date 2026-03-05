# Thermal stress test

Runs `dcgmproftester12` on all GPUs and collects temperature / power / throttle
telemetry via `nvidia-smi` for each node.

## Usage

Pass `--gpus-per-node` on the `sbatch` command line:

```bash
# H100 (8 GPUs per node)
sbatch --gpus-per-node=8 -w ccw-gpu-[1-10] thermal_test.slurm

# GB300 (4 GPUs per node)
sbatch --gpus-per-node=4 -w ccw-gpu-[1-10] thermal_test.slurm
```
