"""Utilities for configuring and creating SlurmExecutor instances for NeMo jobs.

This module provides a helper function to create and configure a SlurmExecutor object from the nemo_run package. 
Through the use of this utility, you can simplify and standardize the creation of Slurm job executors for NeMo experiments.
"""
from typing import Optional
import nemo_run as run

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
    gres: str = "none",
) -> run.SlurmExecutor:
    """
    Create and configure a SlurmExecutor for NeMo jobs.

    Args:
        account (str): Slurm account name.
        partition (str): Slurm partition to submit the job to.
        nodes (int): Number of nodes to use.
        devices (int): Number of devices (GPUs) per node.
        time (str, optional): Walltime for the job. Defaults to "01:00:00".
        custom_mounts (list[str], optional): Additional container mounts.
        custom_env_vars (dict[str, str], optional): Additional environment variables.
        container_image (str, optional): Container image to use. Defaults to "nvcr.io#nvidia/nemo:dev".
        retries (int, optional): Number of retries for the job. Defaults to 0.
        gres (str, optional): Generic resources string for Slurm.

    Returns:
        run.SlurmExecutor: Configured SlurmExecutor instance.
    """

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
