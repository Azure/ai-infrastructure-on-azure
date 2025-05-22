import nemo_run as run
from typing import Optional

def slurm_executor(
    #user: str,
    #host: str,
    #remote_job_dir: str,
    account: str,
    partition: str,
    nodes: int,
    devices: int,
    time: str = "01:00:00",
    custom_mounts: Optional[list[str]] = None,
    custom_env_vars: Optional[dict[str, str]] = None,
    container_image: str = "nvcr.io#nvidia/nemo:dev",
    retries: int = 0,
    gres: str = None,
) -> run.SlurmExecutor:

    mounts = []
    # Custom mounts are defined here.
    if custom_mounts:
        mounts.extend(custom_mounts)

    # Env vars for jobs are configured here
    env_vars = {
        "TORCH_NCCL_AVOID_RECORD_STREAMS": "1",
        "NCCL_NVLS_ENABLE": "0",
        "NVTE_DP_AMAX_REDUCE_INTERVAL": "0",
        "NVTE_ASYNC_AMAX_REDUCTION": "1",
    }
    if custom_env_vars:
        env_vars |= custom_env_vars

    local_tunnel = run.LocalTunnel(job_dir='')
    # This defines the slurm executor.
    # We connect to the executor via the tunnel defined by user, host, and remote_job_dir.
    executor = run.SlurmExecutor(
        account=account,
        partition=partition,
        tunnel=local_tunnel,
        nodes=nodes,
        ntasks_per_node=devices,
        gpus_per_node=devices,
        mem="0",
        exclusive=True,
        gres=gres,
        packager=run.Packager(),
    )

    executor.container_image = container_image
    executor.container_mounts = mounts
    executor.env_vars = env_vars
    executor.retries = retries
    executor.time = time

    return executor