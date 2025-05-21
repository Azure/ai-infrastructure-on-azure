# LLM Foundry MPT Training

## Table of Contents

1. [Introduction](#introduction)
2. [Building the container](#building-the-container)

## Introduction

In this example, we will demonstrate how to train a Mosaic Pretrained Transformer (MPT) model, using a slurm cluster.

The references that have been used to build this example are:

- [LLM-Foundry](https://github.com/mosaicml/llm-foundry) - a framework by MosaicML for training, fine-tuning, and deploying large language models efficiently
- [LLM-Foundry Training Walkthrough](https://github.com/mosaicml/llm-foundry/tree/main/scripts/train) - example training scripts
- [C4 (Colossal, Cleaned, Common Crawl) Dataset](https://huggingface.co/datasets/allenai/c4) - training dataset for the models
- [Azure CycleCloud Workspaces for Slurm](https://github.com/Azure/cyclecloud-slurm-workspace) - The Azure Marketplace offering allowing to stand-up a Slurm cluster powered by Azure CycleCloud and Azure Storage, with pre-configured `enroot` and `pyxis` to support containerized workloads

## Creating Azure CycleCloud Workspaces for Slurm Environment

The first step in the process implies the creation of an Azure CycleCloud Slurm Workspace environment. The documentation [available in Microsoft Learn](https://learn.microsoft.com/en-us/azure/cyclecloud/overview-ccws?view=cyclecloud-8) guides through the deployment process.

This can be done through infrastrucutre as code [following the infrastructure reference example](../../../../infrastructure_references/azure_cyclecloud_workspaces_for_slurm/README.md).

The Azure environment suggested for the following example should contain:

- A GPU partition `gpu` with ND-series nodes. The example has been tested on `Standard_ND96isr_H100_v5` and `Standard_ND96isr_H200_v5`. This will be `GPU_SKU` environment variable in the deployment reference documentation.
- Any sort of NFS home directory will be suitable for this example.  There are no dependencies here for running this example.
- An Azure Managed Lustre File System for the shared cluster area. This will be used for training data storage and checkpointing.

The Azure Managed Lustre File System should be sized with the following considerations:

- The training data read requires minimal bandwidth.  Any latencies can be hidden through the local storage.  Data can be predownloaded in the background.
- Checkpointing will demand higher bandwidth and particularly if shared reads and writes are used.  The Lustre file system should be sized to accommodate the number of GPUs and the expected checkpoint size.  The mpt-30b model has a checkpoint size of 336 GiB and the mpt-70b model has a checkpoint size of 725 GiB.  The Lustre file system should be sized to accommodate reading and writing of these files in parallel to improved the operation times.  If a single file is used there will be a limit of 10GBps.
- Squash files are used to store the container image.  The size of the squash file is 21 GiB.  All nodes will read this file at the start of the job - but this can be staged to the NVME to reduce bandwidth requirement for Lustre.  More details can be found [here](../../../../storage_references/squashed_images/README.md).

## Building the container

Copy the Dockerfile to your cluster and build the container as follows:

```
sudo docker build -t llm-foundry:v0.18.0 -f Dockerfile .
```

Convert the Docker image into a squash file:

```
sudo enroot import -o llm-foundry-v0.18.0.sqsh dockerd://llm-foundry:v0.18.0
```

## Dataset preparation

LLM Foundry provides a script to download and convert datasets from huggingface. The script is located in the `scripts/data_prep` directory of the LLM Foundry repository. The script can be run as follows to download and convert the full [C4](https://huggingface.co/datasets/allenai/c4) dataset.  First, start a container to use:

```
DATA_DIR=/data
srun --cpu-bind no -N1 --exclusive -p gpu --container-image llm-foundrty-0.18.0.sqsh --gres=gpu:8 --container-mounts $DATA_DIR:$DATA_DIR --pty bash
```

Now, download and convert the data:

```
python /llm-foundry/scripts/data_prep/convert_dataset_hf.py \
  --dataset allenai/c4 \
  --data_subset en \
  --out_root /data/my-copy-c4 \
  --splits train val \
  --concat_tokens 2048 \
  --tokenizer EleutherAI/gpt-neox-20b \
  --eos_text '<|endoftext|>' \
  --num_workers 8
```

Alternatively, an sbatch script, `download_c4_data.sh`, is provided to perform the download and conversion:

```
DATA_DIR=/data
CONTAINER_NAME=llm-foundry-v0.18.0.sqsh
NUM_WORKERS=8
sbatch -N1 -p gpu download_c4_data.sh $CONTAINER_NAME $DATA_DIR $NUM_WORKERS
```

> The `NUM_WORKERS` variable is used to specify the number of workers to use for downloading and converting the dataset. A higher value will increase the speed of the download and conversion process.  However, this may need to be lowered if throttling is observed.

## Training run

The example training configuration files are located in the `/llm-foundry/scripts/train/yamls/pretrain/` directory.  The example here has been run with the `mpt-30b` and `mpt-70b` configurations.  Below is an example of how to launch composer in an sbatch script:

```
srun -l \
    --cpu-bind no \
    --container-image $IMAGE \
    --container-mounts $MOUNTS \
    bash -c "composer \
    --world_size $WORLD_SIZE \
    --node_rank \$SLURM_NODEID \
    --master_addr $MASTER_ADDR \
    --master_port $MASTER_PORT \
    --verbose \
    /llm-foundry/scripts/train/train.py \
    /llm-foundry/scripts/train/yamls/pretrain/mpt-30b.yaml \
    $YAML_UPDATES
```

The `YAML_UPDATES` can be used to create/overide variables in the YAML file.  This is in the form of space separated `key=value` pairs.  The following sections describe some of the options that have been tested and is followed by an overview of the `launch.sb` script that provides a utility script to set these values.

### Checkpointing

The parameters to control the checkpointing are:

* `save_interval`: The interval at which the checkpoints are saved (the unit needs to be set, e.g. `ba` for batches)
* `save_num_checkpoints_to_keep`: The number of checkpoints to keep.  The oldest checkpoints will be deleted.
* `save_folder`: The folder where the checkpoints will be saved.

The `fdsp_config.state_dict_type` setting determines how model checkpoints are saved.  The default is `full` and aggregates all the data to a single process and writes a single file for the whole model.  However, `sharded` saves the model in parallel across multiple processes, offering faster read and write times and requiring high-bandwidth storage like Azure Managed Lustre or Azure Blob Storage. A key consideration with sharded is that reloading typically requires the same number of processes used for saving. The choice depends on balancing I/O performance, storage capabilities, and the flexibility needed for restarting or loading checkpoints.

### Preloading to local storage




### Example sbatch script

This `scripts/launch.sb` script can be used to launch one of the example jobs in LLM Foundry.

#### Arguments

- `-c <config>`  
  Specifies the configuration file for the training. This is a required argument. The config file should be located in the `/llm-foundry/scripts/train/yamls/pretrain/` directory.

- `-i <image>`  
  Specifies the container image to use for the training job. This argument is required.

- `-d <datadir>`  
  Specifies the path to the data directory. This argument is required.

- `-s`  
  Enables checkpointing during training. This flag is optional. If specified, additional checkpointing arguments must be provided (e.g., `-I`, `-N`, `-F`).

- `-I <save_interval>`  
  Sets the interval (in steps) at which checkpoints will be saved. This argument is optional and defaults to 1000 if checkpointing (`-s`) is enabled.

- `-N <save_num_checkpoints_to_keep>`  
  Specifies the number of recent checkpoints to keep. Older checkpoints will be deleted. This argument is optional and defaults to 1 if checkpointing (`-s`) is enabled.

- `-F <save_folder>`  
  Specifies the folder where checkpoints will be saved. This argument is required if checkpointing (`-s`) is enabled. The folder path must be provided.

- `-u <usesharp>`  
  Enables SHARP (a communication library) for optimized collective operations. Set this to `1` to enable SHARP, or `0` to disable it. This argument is optional. Defaults to `0`.

- `-S`  
  Enables sharded checkpointing. This flag is optional. If specified, the `fsdp_config.state_dict_type` will be set to `sharded`.

- `-m <mounts>`  
  Specifies the container mount paths. This argument is required. Multiple mounts should be separated by commas (e.g., `/data:/data,/blob:/blob`).

- `-y <yaml_updates>`  
  Provides additional YAML variable updates to be passed during training. This argument is optional. It allows you to dynamically override specific values in the YAML config file.


## Appendix A: Setting up docker to use the nvme

```
sudo systemctl stop docker
sudo mv /etc/docker/daemon.json /etc/docker/daemon.json.old
jq '. + {"data-root": "/mnt/nvme/docker-root"}' /etc/docker/daemon.json.old | sudo tee /etc/docker/daemon.json
sudo systemctl start docker
```

## Appendix B: Profiling

profiling:
    schedule:
        skip_first: 0,
        wait: 0,
        warmup: 1,
        active: 4,
        repeat: 1,
    json_trace_handler:
        

```
    # Profiling
    profiler: Optional[Profiler] = None
    profiler_cfg = train_cfg.profiler
    if profiler_cfg:
        profiler_schedule_cfg: dict = pop_config(
            profiler_cfg,
            'schedule',
            must_exist=True,
        )
        profiler_schedule = cyclic_schedule(**profiler_schedule_cfg)
        # Only support json trace handler
        profiler_trace_handlers: list[TraceHandler] = []
        profiler_trace_cfg: Optional[dict] = pop_config(
            profiler_cfg,
            'json_trace_handler',
            must_exist=False,
            default_value=None,
        )
        if profiler_trace_cfg:
            profiler_trace_handlers.append(
                JSONTraceHandler(**profiler_trace_cfg),
            )
        profiler = Profiler(
            **profiler_cfg,
            trace_handlers=profiler_trace_handlers,
            schedule=profiler_schedule,
        )
```


Benchmarks using the example from the main [repo](https://github.com/mosaicml/llm-foundry/tree/main).


## Setting up the nodes

GPUs are in persistent mode and clocks are fixed:

```
sudo nvidia-smi -pm 1
sudo nvidia-smi -lgc 1980
sudo nvidia-smi -ac 2619,1980
```


## Blobfuse

Use different containers for checkpoints and data.  The main thing to consider for BLOB is the number of transactions as this is a cost.  Keeping the blocksize high will limit this.  However, for training data, this could bring in more that is required and end up with bandwidth throttling.  Running with different configurations and looking at the transactions, egress and ingress can help optimise parameters.

![BLOB Metrics](blob-metrics.png)

Below are the config files used.  They were mounted on the nodes as follows:

```
sudo blobfuse2 mount /blob --config-file <config-file> --tmp-path=/mnt/nvme/blobfuse -o allow_other
```

### Data container

```
logging:
  type: syslog
  level: log_debug

components:
  - libfuse
  - block_cache
  - attr_cache
  - azstorage

libfuse:
  attribute-expiration-sec: 120
  entry-expiration-sec: 120
  negative-entry-expiration-sec: 240

block_cache:
  block-size-mb: 16 
  mem-size-mb: 65536
  prefetch: 16
  prefetch-on-open: false
  parallelism: 128

attr_cache:
  timeout-sec: 7200

azstorage:
  type: block
  account-name: ccswblobstore
  mode: msi
  container: data
  appid: <insert-app-id>
```

### Checkpoint container:

```
logging:
  type: syslog
  level: log_debug

components:
  - libfuse
  - block_cache
  - attr_cache
  - azstorage

libfuse:
  attribute-expiration-sec: 120
  entry-expiration-sec: 120
  negative-entry-expiration-sec: 240

block_cache:
  block-size-mb: 32
  mem-size-mb: 65536
  prefetch: 80
  parallelism: 128

attr_cache:
  timeout-sec: 7200

azstorage:
  type: block
  account-name: ccswblobstore
  mode: msi
  container: checkpoints
  appid: <insert-app-id>
```


### Example Usage

```
sbatch -N 16 -p gpu ./scripts/launch.sb -c mpt-30b -i /data/llm-foundry-v0.18.0.sqsh -d /data/my-copy-c4-full -s -I 10 -N 5 -F /data/checkpoints -S -m /data:/data
```



sbatch -N 32 -p gpu ./launch_test.sb -c mpt-30b -i /data/llm-foundry-v0.18.0.sqsh -d /data/paedwar/my-copy-c4-full -s -I 100 -N 5 -F /mnt/nvme/paedwar/checkpoints -S -m /data:/data

## Results




sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-30b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /blob_data_auto/paedwar/data/my-copy-c4-full -I 100 -N 5 -F /mnt/nvme/paedwar/checkpoints-32n -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_auto:/blob_data_auto -y max_duration=100ba

sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-70b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /blob_data_auto/paedwar/data/my-copy-c4-full -I 100 -N 5 -F /mnt/nvme/paedwar/checkpoints-32n -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_auto:/blob_data_auto -y max_duration=100ba

sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-30b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -I 100 -N 5 -F /mnt/nvme/paedwar/checkpoints-32n -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_auto:/blob_data_auto -y max_duration=100ba

sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-70b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -I 100 -N 5 -F /mnt/nvme/paedwar/checkpoints-32n -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_auto:/blob_data_auto -y max_duration=100ba

# custom-read-1 params
block_cache:
  block-size-mb: 16 
  mem-size-mb: 65536
  prefetch: 16
  prefetch-on-open: false
  parallelism: 128

llmfoundry_1975
sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-30b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /blob_data_read/paedwar/data/my-copy-c4-full -I 100 -N 5 -F /mnt/nvme/paedwar/checkpoints-32n -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_read:/blob_data_read -y max_duration=100ba

llmfoundry_1976
sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-70b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /blob_data_read/paedwar/data/my-copy-c4-full -I 100 -N 5 -F /mnt/nvme/paedwar/checkpoints-32n -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_read:/blob_data_read -y max_duration=100ba




llmfoundry_1952 *
sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-30b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -s -I 1 -N 6 -F /mnt/nvme/paedwar/checkpoints/$(uuidgen) -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_auto:/blob_data_auto -y max_duration=11ba

llmfoundry_1953 *
sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-70b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -s -I 1 -N 6 -F /mnt/nvme/paedwar/checkpoints/$(uuidgen) -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_auto:/blob_data_auto -y max_duration=11ba

llmfoundry_1954 *
sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-30b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -s -I 1 -N 6 -F /blob_data_auto/paedwar/checkpoints/$(uuidgen) -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_auto:/blob_data_auto -y max_duration=11ba

llmfoundry_1955 *
sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-70b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -s -I 1 -N 6 -F /blob_data_auto/paedwar/checkpoints/$(uuidgen) -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_auto:/blob_data_auto -y max_duration=11ba

llmfoundry_1956 *
sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-30b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -s -I 1 -N 6 -F /lustre-fs-480/paedwar/checkpoints/$(uuidgen) -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_auto:/blob_data_auto -y max_duration=11ba

llmfoundry_1957 *
sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-70b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -s -I 1 -N 6 -F /lustre-fs-480/paedwar/checkpoints/$(uuidgen) -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_auto:/blob_data_auto -y max_duration=11ba

llmfoundry_1961
sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-30b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -s -I 1 -N 6 -F /nvme/paedwar/checkpoints/$(uuidgen) -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_auto:/blob_data_auto,/mnt/nvme:/mnt/nvme -y max_duration=11ba

llmfoundry_196
5   sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-70b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -s -I 1 -N 6 -F /mnt/nvme/paedwar/checkpoints/$(uuidgen) -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_auto:/blob_data_auto,/mnt/nvme:/mnt/nvme -y max_duration=11ba


paedwar@ccw-login-1:/data/paedwar/example$ squeue
             JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
              1955       gpu llmfound  paedwar PD       0:00     32 (Resources)
              1956       gpu llmfound  paedwar PD       0:00     32 (Priority)
              1957       gpu llmfound  paedwar PD       0:00     32 (Priority)
              1961       gpu llmfound  paedwar PD       0:00     32 (Priority)
              1962       gpu llmfound  paedwar PD       0:00     32 (Priority)
              1954       gpu llmfound  paedwar  R      56:38     32 ccw-gpu-[1,10,19,37,54,63,108,141-165]  first lustre


-rw-rw-r--  1 paedwar paedwar   2800743 Apr  2 15:57 llmfoundry_1953.out
-rw-rw-r--  1 paedwar paedwar   2812759 Apr  2 17:08 llmfoundry_1954.out


30b 1.31GiB x 256 = 336GiB
70b 2.83GiB x 256 = 725GiB



block_cache:
  block-size-mb: 32
  mem-size-mb: 65536
  prefetch: 80
  parallelism: 128


llmfoundry_1966 *
sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-30b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -s -I 1 -N 6 -F /blob_data/paedwar/checkpoints/$(uuidgen) -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data:/blob_data -y max_duration=11ba

llmfoundry_1967 *
sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-70b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -s -I 1 -N 6 -F /blob_data/paedwar/checkpoints/$(uuidgen) -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data:/blob_data -y max_duration=11ba

file_cache:
  path: /mnt/nvme/blobfuse-cache

#llmfoundry_1983 *
sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-30b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -s -I 1 -N 6 -F /blob_data_filecache/paedwar/checkpoints/$(uuidgen) -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_filecache:/blob_data_filecache -y max_duration=11ba

#llmfoundry_1984 *
sbatch -N 32 -p gpu --reservation=paul ./launch_test.sb -c mpt-70b -i /data/paedwar/llm-foundry-v0.18.0.sqsh -d /lustre-fs-480/paedwar/data/my-copy-c4-full -s -I 1 -N 6 -F /blob_data_filecache/paedwar/checkpoints/$(uuidgen) -S -m /data:/data,/lustre-fs-480:/lustre-fs-480,/blob_data_filecache:/blob_data_filecache -y max_duration=11ba







# get metrics

az monitor metrics list --resource "/subscriptions/75d1e0d5-9fed-4ae1-aec7-2ecc19de26fa/resourceGroups/JZ-ccwsamlfs5/providers/Microsoft.Storage/storageAccounts/ccswblobstore" --interval PT1M --metric Ingress --start-time 2025-04-02T17:13:00Z --end-time 2025-04-02T18:45:00Z -o table


# create a reservation for 8 nodes in the gpu partition with slurm

```
sudo scontrol create reservation=paul users=paul nodes=ccw-gpu-[1-8] starttime=now duration=infinite
sudo scontrol delete reservation=paul
scontrol show reservations
```
