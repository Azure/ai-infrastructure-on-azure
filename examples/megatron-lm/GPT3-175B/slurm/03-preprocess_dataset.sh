#!/bin/bash
# This script preprocesses the SlimPajama dataset using NeMo Docker image.
set -ex

TASKS_PER_NODE=${TASKS_PER_NODE:-48}
NNODES=${NNODES:-24}
PARTITION=${PARTITION:-"gpu"}

if [ -z "$STAGE_PATH" ]; then
  echo "Please set the STAGE_PATH environment variable to the path where you want to store the image."
  exit 1
fi

## NEMO
NEMO_VERSION=${NEMO_VERSION:-"24.05"}
DATASET_FOLDER_NAME=${DATASET_FOLDER_NAME:-"slimpajama"}
SQUASHED_NEMO_IMAGE_NAME="nemo+${NEMO_VERSION}"
SQUASHED_NEMO_IMAGE="$STAGE_PATH/${SQUASHED_NEMO_IMAGE_NAME}.sqsh"
RESULTS="$STAGE_PATH/results"

## ENROOT VARIABLES
export MELLANOX_VISIBLE_DEVICES="void"
export NVIDIA_VISIBLE_DEVICES="void"

mkdir -p $RESULTS

python3 $STAGE_PATH/NeMo-Framework-Launcher/launcher_scripts/main.py \
  launcher_scripts_path=$STAGE_PATH/NeMo-Framework-Launcher/launcher_scripts \
  stages=[data_preparation] \
  data_preparation="gpt/download_slim_pajama.yaml" \
  base_results_dir=$RESULTS \
  data_dir=$STAGE_PATH/$DATASET_FOLDER_NAME \
  data_preparation.download_slim_pajama=False \
  data_preparation.extract_slim_pajama=False \
  data_preparation.preprocess_data=True \
  data_preparation.concat_slim_pajama=False \
  data_preparation.run.cpus_per_node=$TASKS_PER_NODE \
  data_preparation.run.ntasks_per_node=$TASKS_PER_NODE \
  data_preparation.run.workers_per_node=$TASKS_PER_NODE \
  data_preparation.run.node_array_size=$NNODES \
  data_preparation.run.results_dir=$STAGE_PATH/results.data_preparation \
  data_preparation.rm_downloaded=False \
  data_preparation.rm_extracted=False \
  cluster.partition=$PARTITION \
  cluster.gpus_per_node=0 \
  env_vars.TRANSFORMERS_OFFLINE=0 \
  container=$SQUASHED_NEMO_IMAGE \
  container_mounts=['/usr/lib/x86_64-linux-gnu/libcuda.so.1:/usr/lib/x86_64-linux-gnu/libcuda.so.1']
