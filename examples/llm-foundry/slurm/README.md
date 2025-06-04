# LLM Foundry MPT Training

## Table of Contents

1. [Introduction](#1-introduction)
2. [Creating Azure CycleCloud Workspace for Slurm Environment](#2-creating-azure-cyclecloud-workspace-for-slurm-environment)

   2.1. [Blob storage for training data and checkpointing](#21-blob-storage-for-training-data-and-checkpointing)

3. [Building the container](#3-building-the-container)
4. [Dataset preparation](#4-dataset-preparation)
5. [Training run](#5-training-run)

   5.1. [Training data storage](#51-training-data-storage)

   5.2. [Checkpointing](#52-checkpointing)

   5.3. [Example Slurm job submissions](#53-example-slurm-job-submissions)

## 1. Introduction

In this example, we will demonstrate how to train a Mosaic Pretrained Transformer (MPT) model, using a slurm cluster.

The references that have been used to build this example are:

- [LLM-Foundry](https://github.com/mosaicml/llm-foundry) - a framework by MosaicML for training, fine-tuning, and deploying large language models efficiently
- [LLM-Foundry Training Walkthrough](https://github.com/mosaicml/llm-foundry/tree/main/scripts/train) - example training scripts
- [C4 (Colossal, Cleaned, Common Crawl) Dataset](https://huggingface.co/datasets/allenai/c4) - training dataset for the models
- [Azure CycleCloud Workspace for Slurm](https://github.com/Azure/cyclecloud-slurm-workspace) - The Azure Marketplace offering allowing to stand-up a Slurm cluster powered by Azure CycleCloud and Azure Storage, with pre-configured `enroot` and `pyxis` to support containerized workloads

## 2. Creating Azure CycleCloud Workspace for Slurm Environment

The guide requires an Azure CycleCloud Slurm Workspace environment. The documentation [available in Microsoft Learn](https://learn.microsoft.com/en-us/azure/cyclecloud/overview-ccws?view=cyclecloud-8) guides through the deployment process.

This can be done through infrastructure as code [following the infrastructure reference example](../../../../infrastructure_references/azure_cyclecloud_workspace_for_slurm/README.md) where the Azure environment suggested for the following example should contain:

- A GPU partition `gpu` with ND-series nodes. The example has been tested on `Standard_ND96isr_H100_v5` and `Standard_ND96isr_H200_v5`. This will be `GPU_SKU` environment variable in the deployment reference documentation.
- Any sort of NFS home directory will be suitable for this example. There are no dependencies here for running this example.
- An Azure Managed Lustre File System for the shared cluster area. This will be used for training data storage and checkpointing.

The Azure Managed Lustre File System should be sized with the following considerations:

- Reading training data requires minimal bandwidth and LLM Foundry supports streaming the data to local caches in the background to hide any latencies.
- Checkpointing will demand higher bandwidth and particularly if shared reads and writes are used. The Lustre file system should be sized to accommodate the number of GPUs and the expected checkpoint size. The mpt-30b model has a checkpoint size of 336 GiB and the mpt-70b model has a checkpoint size of 725 GiB.
  The Lustre file system should be sized to accommodate reading and writing of these files in parallel to improved the operation times. If a single file is used there will be a limit of 10GBps.
- Squash files are used to store the container image. The size of the squash file generated in this example is 21 GiB. All nodes will read this file at the start of the job - but this can be staged to the NVME to reduce bandwidth requirement for Lustre. More details can be found [here](../../../../storage_references/squashed_images/README.md).

### 2.1. Blob storage for training data and checkpointing

As an alternative to Azure Managed Lustre, Blob storage can be used for the training data and checkpointing. This is a cost effective solution but will require more tuning to get the performance required.  
The Blob storage can be mounted using [blobfuse](https://github.com/Azure/azure-storage-fuse). The default limits for a standard Blob storage account are shown [here](https://learn.microsoft.com/en-us/azure/storage/common/scalability-targets-standard-account) but you can contact [Azure support](https://azure.microsoft.com/support/faq/) to request an increase in account limits if required.
Reading the data is not so much of an issue for the MPT examples if the the dataloader is set to stream to a local cache. This was the higher latency for Blob storage will be hidden.

Block cache performs better in my tests for checkpointing, where the files are streamed rather than uploading/downloading all at once. Below is a template configuration file:

```yaml
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
  account-name: $ACCOUNT_NAME
  mode: msi
  container: $CONTAINER_NAME
  appid: $APP_ID
```

To create the Blob mount on the nodes, you must do the following on each of the nodes:

1. Assign the `Storage Blob Data Contributor` role to the Managed Identity of the VMSS (see [here](https://learn.microsoft.com/en-us/azure/storage/blobs/assign-azure-role-data-access?tabs=portal) for details)
2. Install blobfuse2 on the nodes
   `sudo apt-get install blobfuse2`
3. Create a mount point for the blob storage
   `sudo mkdir /blob`
4. Create the config file from template above (ensure ACCOUNT_NAME, CONTAINER_NAME and APP_ID are set before running)
   `envsubst < blobfuse.template.yaml > blobfuse.yaml`
5. Mount the blob storage using blobfuse
   `sudo blobfuse2 mount /blob --config-file blobfuse.yaml -o allow_other`

> Note: When using Blob storage, check the metrics to ensure you are not being throttled.

## 3. Building the container

Copy the Dockerfile to your cluster and build the container as follows:

```bash
sudo docker build -t llm-foundry:v0.18.0 -f Dockerfile .
```

Convert the Docker image into a squash file:

```bash
sudo enroot import -o llm-foundry-v0.18.0.sqsh dockerd://llm-foundry:v0.18.0
```

## 4. Dataset preparation

LLM Foundry provides a script to download and convert datasets from huggingface. The script is located in the `scripts/data_prep` directory of the LLM Foundry repository. The script can be run as follows to download and convert the full [C4](https://huggingface.co/datasets/allenai/c4) dataset. First, start a container to use:

```bash
DATA_DIR=/data
srun --cpu-bind no -N1 --exclusive -p gpu --container-image llm-foundry-0.18.0.sqsh --gres=gpu:8 --container-mounts $DATA_DIR:$DATA_DIR --pty bash
```

Now, download and convert the data:

```bash
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

```bash
DATA_DIR=/data
CONTAINER_NAME=llm-foundry-v0.18.0.sqsh
NUM_WORKERS=8
sbatch -N1 -p gpu download_c4_dataset.sb $CONTAINER_NAME $DATA_DIR $NUM_WORKERS
```

> The `NUM_WORKERS` variable is used to specify the number of workers to use for downloading and converting the dataset. A higher value will increase the speed of the download and conversion process. However, this may need to be lowered if throttling is observed.

## 5. Training run

The example training configuration files are located in the `/llm-foundry/scripts/train/yamls/pretrain/` directory. An example launch script, `launch.sb`, is included:

```bash
#!/bin/bash
#SBATCH --job-name=llmfoundry
#SBATCH --output=%x_%j.out
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-node=8
#SBATCH --gpus-per-task=8
#SBATCH --gres=gpu:8
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1

# Argument parsing
usage() {
    echo "Usage: $0 -c <config> -i <image> -m <mounts> -y <yaml_updates>"
    exit 1
}

while getopts "c:i:m:y:" opt; do
    case ${opt} in
        c) config=$OPTARG ;;
        i) image=$OPTARG ;;
        m) mounts=$OPTARG ;;
        y) yaml_updates=$OPTARG ;;
        *) usage ;;
    esac
done

if [[ -z "$config" || -z "$image" || -z "$mounts" || -z "$mounts" ]]; then
    usage
fi

NODES=( $( scontrol show hostnames $SLURM_JOB_NODELIST ) )
NNODES=${#NODES[@]}
MASTER_ADDR=$(getent hosts ${NODES[0]} | awk '{print $1}')
MASTER_PORT=$(($RANDOM + 1024))
NPROC=8
WORLD_SIZE=$((NNODES * NPROC))

export CUDA_DEVICE_ORDER=PCI_BUS_ID \
       NCCL_SOCKET_IFNAME=eth0 \
       NCCL_DEBUG=INFO \
       UCX_TLS=rc \
       UCX_NET_DEVICES=mlx5_ib0:1 \
       NCCL_IB_QPS_PER_CONNECTION=4 \
       NCCL_IGNORE_CPU_AFFINITY=1 \
       NCCL_P2P_NET_CHUNKSIZE=$((512*1024)) \
       NCCL_PXN_DISABLE=1 \
       NCCL_MIN_NCHANNELS=32 \
       NCCL_TOPO_FILE=/etc/ndv5-topo.xml \
       TRITON_CACHE_DIR=/tmp/triton-cache-$SLURM_JOBID

srun -l \
    --cpu-bind no \
    --container-image $image \
    --container-mounts $mounts \
    bash -c "composer \
    --world_size $WORLD_SIZE \
    --node_rank \$SLURM_NODEID \
    --master_addr $MASTER_ADDR \
    --master_port $MASTER_PORT \
    --verbose \
    /llm-foundry/scripts/train/train.py \
    /llm-foundry/scripts/train/yamls/pretrain/${config}.yaml \
    ${yaml_updates}"
```

The script arguments are:

- `-c <config>`: The name of the configuration file from the LLM Foundry repository to use for training. This has been tested with the `mpt-30b` and `mpt-70b` configurations.
- `-i <image>`: The name of the container image to use for training. This should be the path to the squash file.
- `-m <mounts>`: The container mount paths. This should be a comma separated list of the mount paths to use for the training data and checkpoints.
- `-y <yaml_updates>`: The option for YAML updates can be used to create/override variables in the YAML file. This is in the form of space separated `key=value` pairs.

The following sections describe some of the YAML options that can be used.

### 5.1. Training data storage

LLM Foundry has two paths for data storage: `data_local` and `data_remote`. The minimum requirement is to set `data_local` to a local directory/mount on the nodes. However, using _both_ `data_local` and `data_remote` can provide efficient data streaming, which is particularly beneficial with Blob Storage.

- `data_remote`: This is the primary storage location containing the whole dataset.
- `data_local`: This is for fast local storage on your training VM (e.g. NVMe drives on Azure NDv5 nodes).

If the `data_remote` option is set, the dataloader works by transferring the required data into `data_local` in the background.

In essence, `data_local` is your fast local cache for `data_remote`, hiding latency from cloud storage and maximizing GPU utilization by ensuring data is always available quickly.

### 5.2. Checkpointing

The parameters to control the checkpointing are:

- `save_interval`: The interval at which the checkpoints are saved (the unit needs to be set, e.g. `ba` for batches)
- `save_num_checkpoints_to_keep`: The number of checkpoints to keep. The oldest checkpoints will be deleted.
- `save_folder`: The folder where the checkpoints will be saved.

The `fdsp_config.state_dict_type` setting determines how model checkpoints are saved. The default is `full` and aggregates all the data to a single process and writes a single file for the whole model. However, `sharded` saves the model in parallel across multiple processes, offering faster read and write times and requiring high-bandwidth storage like Azure Managed Lustre or Azure Blob Storage.
A key consideration with sharded is that reloading typically requires the same number of processes used for saving. The choice depends on balancing I/O performance, storage capabilities, and the flexibility needed for restarting or loading checkpoints.

### 5.3. Example Slurm job submissions

This example sets the parameters for sharded checkpoints:

```bash
SQUASH_FILE=/data/llm-foundry-v0.18.0.sqsh
AMLFS_MOUNT=/data

YAML_UPDATES=$(cat <<EOF
variables.data_local=/data/my-copy-c4
save_folder=/data/checkpoints
save_interval=1000ba
save_num_checkpoints_to_keep=10
fsdp_config.state_dict_type=sharded
EOF
)

sbatch -N 16 -p gpu ./launch.sb \
  -c mpt-30b \
  -i SQUASH_FILE \
  -m /$AMLFS_MOUNT:/$AMLFS_MOUNT \
  -y "$YAML_UPDATES"
```

This example streams data to the local disk:

```bash
SQUASH_FILE=/data/llm-foundry-v0.18.0.sqsh
BLOB_MOUNT=/blob

YAML_UPDATES=$(cat <<EOF
variables.data_local=/tmp/local-storage
variables.data_remote=/blob/my-copy-c4
EOF
)

sbatch -N 16 -p gpu ./launch.sb \
  -c mpt-30b \
  -i SQUASH_FILE \
  -m /$BLOB_MOUNT:/$BLOB_MOUNT \
  -y "$YAML_UPDATES"
```
