# Multi-node NCCL all_reduce test

Uses per-generation config files in `configs/` for GPU count, CPU pinning, and
NCCL tuning. A launcher script reads the config and passes the correct resource
directives to `sbatch`.

## Directory structure

```
NCCL/
  configs/
    hopper.conf         # Hopper (H100 / H200) — 8 GPUs, SHARP/CollNet
    graceblackwell.conf # Grace Blackwell (GB200 / GB300) — 4 GPUs, MNNVL/NVLS
  nccl_test.sh          # Launcher — reads config, calls sbatch
  nccl_test.slurm       # Batch script  (called by launcher)
  nccl_test_mpirun.sh   # mpirun launcher (sources config directly)
```

## Config files

Each config sets these variables plus generation-specific NCCL exports:

| Variable | Description |
|----------|-------------|
| `GPUS_PER_NODE` | Number of GPUs per node |
| `TASKS_PER_NODE` | MPI ranks per node (typically = GPUs) |
| `CPUS_PER_TASK` | CPU cores allocated per rank |
| `CPU_BIND` | `srun --cpu-bind` value (`none` or `mask_cpu:...`) |

To add a new GPU generation, create a new `.conf` file in `configs/`.
To override settings for a specific SKU within a generation, create a
SKU-specific config that sources the parent, e.g.:

```bash
# configs/h200.conf — H200-specific overrides
source "${BASH_SOURCE%/*}/hopper.conf"
export SOME_SETTING=override
```

## 1. Launch with SLURM

Use the launcher script — it reads the config and submits with correct
`--gpus-per-node`, `--ntasks-per-node`, and `--cpus-per-task`:

```bash
# Auto-detect generation (probes first node via ssh)
./nccl_test.sh -N 4 -w ccw-gpu-[1-4]

# Explicit generation
SKU=graceblackwell ./nccl_test.sh -N 4 -w ccw-gpu-[1-4]
SKU=hopper         ./nccl_test.sh -N 10 -w ccw-gpu-[1-10]
```

## 2. Launch with mpirun

```bash
# Auto-detect generation (probes first host via ssh)
./nccl_test_mpirun.sh ccw-gpu-[1-10]

# Explicit generation
SKU=graceblackwell ./nccl_test_mpirun.sh ccw-gpu-[1-4]
```
