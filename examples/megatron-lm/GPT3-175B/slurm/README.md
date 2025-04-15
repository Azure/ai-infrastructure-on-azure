# Megatron-LM Distributed Training - GPT3 - 175B

## Table of Contents
1. [Introduction](#introduction)
2. [Creation of an Azure CycleCloud Workspaces for Slurm environment](#1-creation-of-an-azure-cyclecloud-workspaces-for-slurm-environment)
3. [Environment setup](#2-environment-setup)
4. [Filesystem Tuning](#3-filesystem-tuning)
5. [Data Preparation](#4-data-preparation)
6. [Training](#5-training-run)
## Introduction
In this example, we will demonstrate how to train a 175B GPT3 model on Azure, using a Slurm cluster.

The references that have been used to build this example are:
* [Megatron-LM](https://github.com/NVIDIA/Megatron-LM) - NVIDIA MegatronLM framework 
* [Megatron-LM GPT175B example](https://github.com/NVIDIA/Megatron-LM/blob/main/examples/gpt3/train_gpt3_175b_distributed.sh) - Example from the MegatronLM repository for GPT175B model
* [SlimPajama 627B Dataset](https://huggingface.co/datasets/cerebras/SlimPajama-627B) - Cleaned and de-duplicated opensource version of Together's RedPajama. Please check the licensing of the different dataset sources before using in your enterprise environment. This dataset is composed of 59,166 jsonl files and a total of approximately 900 GiB of compressed data
* [Azure CycleCloud Workspaces for Slurm](https://github.com/Azure/cyclecloud-slurm-workspace) - The Azure Marketplace offering allowing to stand-up a Slurm cluster powered by Azure CycleCloud and Azure Storage, with pre-configured `enroot` and `pyxis` support

All the scripts and code that have been derived by any of the above repositories will be explicitly marked and will contain the proper copyright disclaimer according to the relative licensing.

## 1. Creation of an Azure CycleCloud Workspaces for Slurm environment

The first step in the process implies the creation of an Azure CycleCloud Slurm Workspace environment. The documentation [available in Microsoft Learn](https://learn.microsoft.com/en-us/azure/cyclecloud/overview-ccws?view=cyclecloud-8) guides through the deployment process.

The Azure environment suggested for the following example should contain:
* A GPU partition with ND-series nodes. The example has been tested on `Standard_ND96isr_H100_v5` and `Standard_ND96isr_H200_v5`
* A HTC partition with general purpose compute nodes for data preparation. For example a `Standard_D64ds_v5`. Please consider that:
    * The files are downloaded in `zst` format, so they will require extraction. This process can be ideally fully parallelized with 1 process per file.
    * In the current dataset processing flow, the `jsonl` files will be concatenated in a total of 72 chunks. This means that for data pre-processing, the parallelism can be pushed up to approximately 72 process in parallel
* An Azure NetApp Files Premium area of approximately `4TiB` for the user environment and home directories
* An Azure Managed Lustre File System for the shared cluster area for data pre-processing, training data storage and checkpointing. Consider that the selected model size (independently from the number of nodes used) will save checkpoint data of approximately `2.3 TiB`. Consider that the AMLFS tier and size will determine the time (in case of use of synchronous checkpoint), as described below.

| Tier  | Size [TiB] | Bandwidth [GB/s] | Theoretical checkpoint write time (min)  |
|----------|----------|----------|--------|
| AMLFS 40   | 480 | 19.2 | 2.04     |
| AMLFS 125    | 512  | 64 | 0.61     |
| AMLFS 250    | 512  | 128 | 0.31     |
| AMLFS 500    | 512  | 256 | 0.15     |


## 2. Environment setup 
In order to prepare the environment, there are several components to be downloaded for the execution.

This will include:
* [PyTorch NGC Image](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/pytorch) - defaults to version `25.03`
* [Nemo Frameweork Launcher Scripts](https://github.com/NVIDIA/NeMo-Framework-Launcher) - defaults to `24.12`
* [Megatron-LM](https://github.com/NVIDIA/Megatron-LM) - defaults to commit `e958b2ca`

The above version can be overriden with the environment variables described in `setup_environment.sh` script file.

A stage path folder should be identified for environment setup. This will contain all the scripts and input training data on the AMLFS volume.

Here, we are here assuming that the `hpc` partition will be used for data preparation:

```bash
export STAGE_PATH=<lustre-folder>
mkdir -p $STAGE_PATH
sbatch -p hpc 00-setup_environment.sh
```

## 3. Filesystem tuning 

During the training job startup, all the cluster nodes will read the squashed image files from the parallel file-system, generating a start-up storm on a single file read.

This means that approximately 23 GiB of data will be read in a single file by hunderds of nodes, requiring an overall egress in the order of several TiBs from the filesystem.

If the image files just have default Lustre striping configuration, this may lead to get most of the pressure in I\O on a limited number of OSSs.

To avoid this issue, there are two alternatives:
* Tuning the Lustre file striping on Lustre
* At job start-up, rsyncing the image file on the nodes local NVME

Here we will demonstrate the commands that would allow the tuning on AMLFS side.

If we run the `lfs getstripe` command on one of the downloaded image, we will see that only 6 OSSs are hosting the file. Moreover, a sequential read of the file by all the nodes on job startup will probably make only even less OSSs contributing at any given time.

```
lfs getsripe $STAGE_PATH/pytorch+25.03+py3.sqsh
...
     lmm_objects:
      - 0: { l_ost_idx: 5, l_fid: [0x100050000:0x38418:0x0] }
...
      lmm_objects:
      - 0: { l_ost_idx: 3, l_fid: [0x100030000:0x38369:0x0] }
      - 1: { l_ost_idx: 9, l_fid: [0x100090000:0x383c6:0x0] }
      - 2: { l_ost_idx: 8, l_fid: [0x100080000:0x3833f:0x0] }
      - 3: { l_ost_idx: 4, l_fid: [0x100040000:0x38338:0x0] }
      - 4: { l_ost_idx: 2, l_fid: [0x100020000:0x3841c:0x0] }
```

In order to increase the read performanc, it is possible to create a number of mirrors of the file components in order to fulfill, or even oversubscribe the OSSs.

In order to count the number of OSS of your filesystem:

```
lfs df -h <MOUNT_POINT>  | grep OST | wc -l
```

In this case, the performace can enhanced adding to the image a number of mirrors able to create stripes on all the OSSs:
```
lfs mirror extend -N2 $STAGE_PATH/<IMAGE_NAME>.sqsh
```

In a similar way, the striping of the single mirror can be increased (this requires superuser priviledges):
```
lfs setstripe -S 512M -E -1 -c -1 $STAGE_PATH/<IMAGE_NAME>.sqsh
```

Here is a comparison on an `AMLFS 500 - 256 TiB` of the time to startup with `srun` a squashed image from the Azure Managed Lustre Filesystem with different settings:

| Setting  |  OST occupation | Container startup time on 64 nodes [s]  |
|----------|----------|----------|
| No mirror / Default striping | 1 x 23 GiB | 218  |
| 5 mirror / Default striping    | 5 x 23 GiB  | 56    |
| 10 mirror / Default striping    | 10 x 23 GiB  | 57   |
| No mirror / Full 64 OST striping   | 1 x 23 GiB  | 105  |
| 5 mirror / Full 64 OST striping    | 5 x 23 GiB  | 73  |
| 10 mirror / Full 64 OST striping    | 10 x 23 GiB  |  70  |


## 4. Data preparation

### Data set download

The SlimPajama dataset has a compressed dimension of approximately 900 TiB. 

Considering the data volume involved, we strongly orient user towards the guidance for [dataset download from Huggingface](https://huggingface.co/docs/hub/datasets-downloading)

Downloading without any Huggingface plan will cause throttling in case of parallel download and using a shared IP.
In order to download the dataset, a convenience script is provided in the repository, and it is called ```download_dataset.py```. This will just download the file sequentially, 1 after the other. It can run even on the head-node. 

This script is based on the examples from [NVIDIA documentation](https://docs.nvidia.com/dgx-cloud/run-ai/latest/nemo-e2e-example.html) and from [Nemo Framework Launcher scripts](https://github.com/NVIDIA/NeMo-Framework-Launcher/blob/main/launcher_scripts/nemo_launcher/collections/dataprep_scripts/slim_pajama_dataprep/download.py).

The example commandline is:

```
python3 01-download.py $STAGE_PATH/slimpajama
```

This download, if done without using Huggingface methodologies, will take several hours.

You can track the progress in another shell window with:
```
watch "ls $STAGE_PATH/slimpajama/*.zst | wc -l"
```

### Data set extraction and concatenation

 * The dataset extraction will extract data from `zst` format to `jsonl` format in the staging folder
 * The concatenation will consolidate the files in only 72 `jsonl` samples

This step is relying on NVIDIA NeMo Megatron framework and Docker image.

In this example we are deciding to extract the dataset using 32 nodes and 32 tasks per nodes, with the `hpc` partition:

```
export STAGE_PATH=<lustre-folder>
TASKS_PER_NODE=32 NNODES=32 PARTITION=hpc ./02-extract_and_concat_dataset.sh
```

This will generate 2 Slurm array jobs, one for extraction and one for concatenation.

To check the extraction was successful, this should return `72`:
```
ls $STAGE_PATH/slimpajama/train*.jsonl | wc -l
```
#### Troubleshooting

In case some jobs result in failure, please check the logs available for each stage in folder `$STAGE_PATH/results.data_preparation`

### Data set preprocessing

Also this step is relying on NVIDIA NeMo Megatron framework and Docker image.
This will generate the preprocessed dataset with the `bin` and `idx` files in the `$STAGE_PATH/slimpajama/preprocessed` folder.

To run this using 4 nodes and 32 tasks per nodes with the `hpc` partition:

```
export STAGE_PATH=<lustre-folder>
TASKS_PER_NODE=32 NNODES=4 PARTITION=hpc ./03-preprocess_dataset.sh
```

#### Troubleshooting

In case some jobs result in failure, please check the logs available for each stage in folder `$STAGE_PATH/results.data_preparation`

## 5. Training run

After the data preparation is completed, the execution of the training on a certain number of nodes can be simply run using the following command:

The script has been adapted starting from [Megatron-LM GPT175B example](https://github.com/NVIDIA/Megatron-LM/blob/main/examples/gpt3/train_gpt3_175b_distributed.sh)

```bash
export STAGE_PATH=<lustre-folder>
sbatch -p gpu -N <NUMBER_OF_NODES> 04-gpt175B.sh
```

Some elements to take into considerations:
* `CHUNKS` variable defines the number of files used for validation and testing. Default is `15`
* `GLOBAL_BATCH_SIZE` should be scaled accoringly to GPU number. Approximately we suggest `16 x NUMBER OF GPUS` 
* `SAVE_INTERVAL` number of iterations between checkpoint save
* `EVAL_INTERVAL` number of iterations between evaluations
* `NUMBER_OF_ITERATIONS` number of iterations up to completion

This value above have been tuned to create a significant pressure on the storage with checkpointing. To look at the effective defaults refer to the official [Megatron-LM GPT175B example](https://github.com/NVIDIA/Megatron-LM/blob/main/examples/gpt3/train_gpt3_175b_distributed.sh)
