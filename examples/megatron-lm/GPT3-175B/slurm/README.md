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

- [Megatron-LM](https://github.com/NVIDIA/Megatron-LM) - NVIDIA MegatronLM framework
- [Megatron-LM GPT175B example](https://github.com/NVIDIA/Megatron-LM/blob/main/examples/gpt3/train_gpt3_175b_distributed.sh) - Example from the MegatronLM repository for GPT175B model
- [SlimPajama 627B Dataset](https://huggingface.co/datasets/cerebras/SlimPajama-627B) - Cleaned and de-duplicated open source version of Together's RedPajama. Please check the licensing of the different dataset sources before using in your enterprise environment. This dataset is composed of 59,166 jsonl files and a total of approximately 900 GiB of compressed data
- [Azure CycleCloud Workspaces for Slurm](https://github.com/Azure/cyclecloud-slurm-workspace) - The Azure Marketplace offering allowing to stand-up a Slurm cluster powered by Azure CycleCloud and Azure Storage, with pre-configured `enroot` and `pyxis` to support containerized workloads

All the scripts and code that have been derived by any of the above repositories will be explicitly marked and will contain the proper copyright disclaimer according to the relative licensing.

## 1. Creation of an Azure CycleCloud Workspaces for Slurm environment

The first step in the process implies the creation of an Azure CycleCloud Slurm Workspace environment. The documentation [available in Microsoft Learn](https://learn.microsoft.com/en-us/azure/cyclecloud/overview-ccws?view=cyclecloud-8) guides through the deployment process.

This can be done through infrastructure-as-code [following the infrastructure reference example](../../../../infrastructure_references/azure_cyclecloud_workspaces_for_slurm/README.md).

The Azure environment suggested for the following example should contain:

- A GPU partition `gpu` with ND-series nodes. The example has been tested on `Standard_ND96isr_H100_v5` and `Standard_ND96isr_H200_v5`. This will be `GPU_SKU` environment variables in the deployment reference documentation.
- A HTC partition `htc` with general purpose compute nodes for data preparation. For example a `Standard_D64ds_v5`. Please consider that:
  - The files are downloaded in `zst` format, so they will require extraction. This process can be ideally fully parallelized with 1 process per file.
  - In the current dataset processing flow, the `jsonl` files will be concatenated in a total of 72 chunks. This means that for data pre-processing, the parallelism can be pushed up to approximately 72 process in parallel
- An Azure NetApp Files Premium Storage Pool and Volume area. The volume size is `4TiB` for the user environment and home directories. This is `ANF_SKU` and `ANF_SIZE` environment variable in the deployment reference.
- An Azure Managed Lustre File System for the shared cluster area. This will be used for data pre-processing, training data storage and checkpointing. This is `AMLFS_SKU` and `AMLFS_SIZE` environment variable in the deployment reference.

We should consider that the selected model size (independently from the number of nodes used) will save checkpoint data of approximately `2.3 TiB`. Consider that the AMLFS tier and size will determine the time (in case of use of synchronous checkpoint), as described below.

| Tier      | Size [TiB] | Bandwidth [GB/s] | Theoretical checkpoint write time (min) |
| --------- | ---------- | ---------------- | --------------------------------------- |
| AMLFS 40  | 480        | 19.2             | 2.04                                    |
| AMLFS 125 | 512        | 64               | 0.61                                    |
| AMLFS 250 | 512        | 128              | 0.31                                    |
| AMLFS 500 | 512        | 256              | 0.15                                    |

## 2. Environment setup

In order to prepare the environment, there are several components to be downloaded for the execution.

This will include:

- [PyTorch NGC Image](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/pytorch) - defaults to version `25.03`
- [Nemo Frameweork Launcher Scripts](https://github.com/NVIDIA/NeMo-Framework-Launcher) - defaults to `24.12`
- [Megatron-LM](https://github.com/NVIDIA/Megatron-LM) - defaults to commit `e958b2ca`

The above version can be overridden with the environment variables described in `setup_environment.sh` script file.

A stage path folder should be identified for environment setup. This will contain all the scripts and input training data on the AMLFS volume.

Here, we are here assuming that the `hpc` partition will be used for data preparation:

```bash
export STAGE_PATH="your-stage-path"
mkdir -p $STAGE_PATH
sbatch -p hpc 00-setup_environment.sh
```

## 3. Filesystem tuning

To get the best filesystem performance on job startup [please refer to the optimizations](../../../../storage_references/squashed_images/README.md) to be applied to the `sqsh` image file.

## 4. Data preparation

### Data set download

The SlimPajama dataset has a compressed dimension of approximately 900 GiB.

Considering the data volume involved, we strongly orient user towards the guidance for [dataset download from Huggingface](https://huggingface.co/docs/hub/datasets-downloading)

Downloading without any Huggingface plan will cause throttling in case of parallel download and using a shared IP.
In order to download the dataset, a convenience script is provided in the repository, and it is called `download_dataset.py`. This will just download the file sequentially, 1 after the other. It can run even on the head-node.

This script is based on the examples from [NVIDIA documentation](https://docs.nvidia.com/dgx-cloud/run-ai/latest/nemo-e2e-example.html) and from [Nemo Framework Launcher scripts](https://github.com/NVIDIA/NeMo-Framework-Launcher/blob/main/launcher_scripts/nemo_launcher/collections/dataprep_scripts/slim_pajama_dataprep/download.py).

The example commandline could be:

```bash
export STAGE_PATH="your-stage-path"
python3 download_slimpajama.py ${STAGE_PATH}/slimpajama
```

Remember to set the `SQUASHED_NEMO_IMAGE` environment variable in case striping has been applied as described in the [filesystem tuning](#3-filesystem-tuning) section.

This download, if done without using Huggingface methodologies, will take several hours.

You can track the progress in another shell window with:

```bash
watch "ls ${STAGE_PATH}/slimpajama/*.zst | wc -l"
```

### Data set extraction and concatenation

- The dataset extraction will extract data from `zst` format to `jsonl` format in the staging folder
- The concatenation will consolidate the files in only 72 `jsonl` samples

This step is relying on NVIDIA NeMo Megatron framework and Docker image.

In this example we are deciding to extract the dataset using 32 nodes and 32 tasks per nodes, with the `hpc` partition:

```bash
export STAGE_PATH="your-stage-path"
TASKS_PER_NODE=32 NNODES=32 PARTITION=hpc ./02-extract_and_concat_dataset.sh
```

This will generate 2 Slurm array jobs, one for extraction and one for concatenation.

To check the extraction was successful, this should return `72`:

```bash
ls $STAGE_PATH/slimpajama/train*.jsonl | wc -l
```

### Data set preprocessing

Also this step is relying on NVIDIA NeMo Megatron framework and Docker image.
This will generate the preprocessed dataset with the `bin` and `idx` files in the `$STAGE_PATH/slimpajama/preprocessed` folder.

To run this using 4 nodes and 32 tasks per nodes with the `hpc` partition:

```bash
export STAGE_PATH="your-stage-path"
TASKS_PER_NODE=32 NNODES=4 PARTITION=hpc ./03-preprocess_dataset.sh
```

### Troubleshooting data preparation phases

In case some jobs result in failure, please check the logs available for each stage in folder `$STAGE_PATH/results.data_preparation`

## 5. Training run

After the data preparation is completed, the execution of the training on a certain number of nodes can be simply run using the following command:

The script has been adapted starting from [Megatron-LM GPT175B example](https://github.com/NVIDIA/Megatron-LM/blob/main/examples/gpt3/train_gpt3_175b_distributed.sh)

The script in the repository runs a GPT3 175B model, but it is possible to do a simple system check on 2 nodes running an example with 375M parameters that allows to validate internode communication and environment configuration:

```bash
export STAGE_PATH="your-stage-path"
export NUM_LAYERS=12
export HIDDEN_SIZE=512
export NUM_ATTENTION_HEADS=8
export SEQ_LENGTH=1024
export TENSOR_MODEL_PARALLEL_SIZE=1
export PIPELINE_MODEL_PARALLEL_SIZE=1
sbatch -p gpu -N 2 04-gpt175B.sh
```

Remember to set the `SQUASHED_PYTORCH_IMAGE` environment variable in case striping has been applied as described in the [filesystem tuning](#3-filesystem-tuning) section.

After validation on the smaller size model, it is possible to move to the larger size model with more confidence:

```bash
export STAGE_PATH="your-stage-path"
unset NUM_LAYERS
unset HIDDEN_SIZE
unset NUM_ATTENTION_HEADS
unset SEQ_LENGTH
unset TENSOR_MODEL_PARALLEL_SIZE
unset PIPELINE_MODEL_PARALLEL_SIZE
sbatch -p gpu -N <NUMBER_OF_NODES> 04-gpt175B.sh
```

The job progress can be monitored looking at the job logs, where `SLURM_JOB_ID` is the ID of the Slurm job in progress:

```bash
tail -f gpt175b_<SLURM_JOB_ID>.*
```

Some elements to take into considerations:

- `CHUNKS` variable defines the number of files used for validation and testing. Default is `15`
- `GLOBAL_BATCH_SIZE` should be scaled accordingly to GPU number. Default is `512` Approximately we suggest `16 x NUMBER OF GPUS`
- `SAVE_INTERVAL` number of iterations between checkpoint save. Default is `10000`, but it can be decreased to generate higher frequency checkpointing.
- `EVAL_INTERVAL` number of iterations between evaluations. Default is `1000`.
- `NUMBER_OF_ITERATIONS` number of iterations up to completion

This value above have been tuned to create a significant pressure on the storage with checkpointing. To look at the effective defaults refer to the official [Megatron-LM GPT175B example](https://github.com/NVIDIA/Megatron-LM/blob/main/examples/gpt3/train_gpt3_175b_distributed.sh)

It is possible to change the model configuration through the aforementioned environment variables. For example for a 857M model:

```bash
export NUM_LAYERS=24
export HIDDEN_SIZE=1024
export NUM_ATTENTION_HEADS=16
export SEQ_LENGTH=2048
export TENSOR_MODEL_PARALLEL_SIZE=1
export PIPELINE_MODEL_PARALLEL_SIZE=1
```

This can be tuned according to the related [table from the NVIDIA MegatronLM repository](https://github.com/NVIDIA/Megatron-LM/blob/main/images/model_table.png?raw=true).
