---
name: thermal-stress-test
description: "Run GPU thermal stress tests using dcgmproftester. Interpret pass/fail results, check temperatures, throttle reasons, and DCGMI diagnostic levels."
---

# Thermal Stress Test

How to run GPU thermal stress tests using dcgmproftester and interpret the results.

> **Scripts**: This skill references test scripts from the [Azure/ai-infrastructure-on-azure](https://github.com/Azure/ai-infrastructure-on-azure) repo. Clone it and run from the repo root.

## What It Tests

dcgmproftester drives sustained GPU compute load to stress thermal limits. The test verifies that GPUs can maintain target performance under full thermal load without throttling or errors. A healthy GPU sustains the target workload for the full duration; a failing GPU throttles, produces errors, or crashes.

## Running the Test

### Slurm batch script

The script is at `infrastructure_validations/slurm/thermal_test/thermal_test.slurm`.

```bash
# Test 4 nodes, 4 GPUs each (GB300) — 15-minute stress
sbatch --gpus-per-node=4 -N 4 thermal_test.slurm

# Test 2 nodes, 8 GPUs each (H100)
sbatch --gpus-per-node=8 -N 2 thermal_test.slurm

# Target specific nodes
sbatch --gpus-per-node=4 -N 1 -w ccw-gpu-1 thermal_test.slurm
```

### Test parameters (hardcoded in thermal_test.sh)

| Parameter | Value | Description |
|-----------|-------|-------------|
| `DURATION` | 900 (15 min) | Stress test duration in seconds |
| Target activity | 1004 | dcgmproftester stress workload ID |
| Binary | auto-detected | `dcgmproftester13` (preferred) or `dcgmproftester12` |

### dcgmproftester binary location

The script auto-detects the binary:

```bash
command -v dcgmproftester13 || command -v dcgmproftester12
```

On current Azure HPC images, `dcgmproftester13` is the available version.

### Manual single-GPU test

```bash
CUDA_VISIBLE_DEVICES=0 dcgmproftester13 --no-dcgm-validation -t 1004 -d 900
```

## How the Test Works

1. `thermal_test.slurm` runs `srun --ntasks-per-node=1` to execute `thermal_test.sh` once per node.
2. `thermal_test.sh` launches one `dcgmproftester` process per GPU in parallel (using `CUDA_VISIBLE_DEVICES`).
3. Each process runs for `DURATION` seconds.
4. After all processes complete, the script checks each process's exit code.
5. A non-zero exit code for any GPU means that GPU failed the thermal test.

## Output Format

```
Starting thermal test on node ccw-gpu-1 (4 GPUs, 900s)...
All 4 GPU thermal tests passed on ccw-gpu-1!
```

Or on failure:

```
GPU 2 FAILED thermal test on ccw-gpu-1 (exit code 1)
THERMAL TEST FAILED on ccw-gpu-1: 1 of 4 GPUs failed
```

## Interpreting Results

### Pass
All GPUs sustain the workload for the full duration. The GPU maintained safe temperatures under load.

### Fail
One or more GPUs could not sustain the workload. Common reasons:
- **Thermal throttling**: GPU junction temperature exceeded safe limits, causing clock reduction that dropped below target.
- **ECC errors under load**: Heat-induced memory errors.
- **GPU hang / XID error**: The GPU stopped responding during the stress test.
- **Power capping**: Power delivery issue preventing sustained boost clocks.

## Supplementary Diagnostics

When a thermal test fails, gather more data:

### GPU temperature and clocks during test

```bash
# Run in parallel with the thermal test on the same node
watch -n 5 'nvidia-smi --query-gpu=index,temperature.gpu,clocks.sm,power.draw --format=csv,noheader,nounits'
```

### Temperature thresholds

```bash
nvidia-smi -q | grep -A2 "Temperature"
```

Look for:
- `GPU Current Temp`: Current temperature
- `GPU T.Limit Temp`: Temperature headroom before throttling (negative = throttling)
- `GPU Shutdown Temp`: Hard shutdown limit

### Clock throttle reasons

```bash
nvidia-smi --query-gpu=index,clocks_event_reasons.active --format=csv,noheader
```

Key throttle reasons:
- `HW Thermal Slowdown` — GPU is too hot
- `SW Thermal Slowdown` — Driver-imposed thermal protection
- `HW Power Brake Slowdown` — External power brake signal
- `SW Power Cap` — Power limit reached

### DCGMI diagnostics (more thorough)

```bash
# Quick check (level 1, ~2 min)
dcgmi diag -r 1

# Extended diagnostics (level 3, ~20-30 min)
dcgmi diag -r 3
```

Level 3 includes stress tests, memory bandwidth, PCIe bandwidth, and NVLink bandwidth checks.

## GHR Category

If a GPU fails thermal testing and the issue persists after reboot:

| Issue | GHR Category |
|-------|-------------|
| Thermal throttling / thermal failure | `gpu_throttling` |
| DCGM diagnostic failure | `dcgm_failure` |
| GPU crashes during stress (XID error) | `xid_79` or `xid_94`/`xid_95` depending on XID code |
