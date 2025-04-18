#!/bin/bash
#SBATCH --job-name=gpt175b
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-node=8
#SBATCH --cpus-per-task=8
#SBATCH --gpus-per-task=8
#SBATCH --mem=0
#SBATCH --output=gpt175b_%j.out
#SBATCH --error=gpt175b_%j.err
# Copyright (c) 2022, NVIDIA CORPORATION. All rights reserved.
# This script has been modified from https://github.com/NVIDIA/Megatron-LM/blob/main/examples/gpt3/train_gpt3_175b_distributed.sh
# It contains the procedure to run the training of GPT-3 175B model using Megatron-LM.
set -xe

if [ -z "$STAGE_PATH" ]; then
	echo "Please set the STAGE_PATH environment variable to the path where you want to store the image."
	exit 1
fi

## CONFIGURATION
TOPO_FILE=${TOPO_FILE:-"/opt/microsoft/ndv5-topo.xml"}
CHUNKS=${CHUNKS:-15}
GLOBAL_BATCH_SIZE=${GLOBAL_BATCH_SIZE:-512}
NUMBER_OF_ITERATIONS=${NUMBER_OF_ITERATIONS:-1500}
SAVE_INTERVAL=${SAVE_INTERVAL:-100}
EVAL_INTERVAL=${EVAL_INTERVAL:-100}
LOGLEVEL=${LOGLEVEL:-"INFO"}

export NCCL_TOPO_FILE=$TOPO_FILE
export CUDA_DEVICE_MAX_CONNECTIONS=1

## PYTORCH
PYTORCH_VERSION=${PYTORCH_VERSION:-"25.03"}
SQUASHED_PYTORCH_IMAGE_NAME="pytorch+${PYTORCH_VERSION}+py3"
SQUASHED_PYTORCH_IMAGE="$STAGE_PATH/${SQUASHED_PYTORCH_IMAGE_NAME}.sqsh"

## PATHS
DATASET_FOLDER_NAME=${DATASET_FOLDER_NAME:-"slimpajama/preprocessed"}
WORK_DIR=${WORK_DIR:-$STAGE_PATH/Megatron-LM}
DATA_PATH=${DATA_PATH:-$STAGE_PATH/$DATASET_FOLDER_NAME}
TENSORBOARD_LOGS_PATH=${TENSORBOARD_LOGS_PATH:-$STAGE_PATH/logs}
CHECKPOINT_PATH=${CHECKPOINT_PATH:-$STAGE_PATH/checkpoints}
VOCAB_FILE=${VOCAB_FILE:-$STAGE_PATH/slimpajama/bpe/vocab.json}
MERGE_FILE=${MERGE_FILE:-$STAGE_PATH/slimpajama/bpe/vocab.json}
DATA_CACHE_DIR=${DATA_CACHE_DIR:-$STAGE_PATH/datacache}

DATA_SET_SIZE=$(find $DATA_PATH -name "*.bin" -type f | wc -l)

TRAIN_DATA="\
 $(find $DATA_PATH -name "*.bin" -type f | sort | head -n $(($DATA_SET_SIZE - $CHUNKS - $CHUNKS)) | xargs -n1 echo 1.0 | sed "s/.bin//g")
"

VALID_DATA="\
 $(find $DATA_PATH -name "*.bin" -type f | sort | tail -n $(($CHUNKS)) | xargs -n1 echo 1.0 | sed "s/.bin//g")
"

TEST_DATA="\
 $(find $DATA_PATH -name "*.bin" -type f | sort | tail -n $(($CHUNKS + $CHUNKS)) | head -n $(($CHUNKS)) | xargs -n1 echo 1.0 | sed "s/.bin//g")
"

DISTRIBUTED_ARGS=(
	--nproc_per_node "$SLURM_GPUS_PER_NODE"
	--nnodes "$SLURM_NNODES"
	--rdzv_id $RANDOM
	--rdzv_backend c10d
	--rdzv_endpoint "$(hostname)":29500
)

GPT_MODEL_ARGS=(
	--num-layers 96
	--hidden-size 12288
	--num-attention-heads 96
	--seq-length 2048
	--max-position-embeddings 2048
	--attention-backend auto
)

TRAINING_ARGS=(
	--micro-batch-size 1
	--global-batch-size "$GLOBAL_BATCH_SIZE" #To be tuned based on number of GPUs. Suggested 16 x GPU number
	--train-iters "$NUMBER_OF_ITERATIONS"    # This is the number of iterations to train for. 1500 is a very low number
	--weight-decay 0.1
	--adam-beta1 0.9
	--adam-beta2 0.95
	--init-method-std 0.006
	--clip-grad 1.0
	--fp16
	--lr 6.0e-5
	--lr-decay-style cosine
	--min-lr 6.0e-6
	--lr-warmup-fraction .001
	--lr-decay-iters 430000
)

MODEL_PARALLEL_ARGS=(
	--tensor-model-parallel-size 8
	--pipeline-model-parallel-size 16
	--sequence-parallel
	--use-distributed-optimizer
)

DATA_ARGS=(
	--data-cache-path "$DATA_CACHE_DIR"
	--train-data-path "$TRAIN_DATA"
	--valid-data-path "$VALID_DATA"
	--test-data-path "$TEST_DATA"
	--vocab-file "$VOCAB_FILE"
	--merge-file "$MERGE_FILE"
)

EVAL_AND_LOGGING_ARGS=(
	--log-interval 10
	--save-interval 100
	--eval-interval 100
	--save "$CHECKPOINT_PATH"
	--load "$CHECKPOINT_PATH"
	--eval-iters 10
	--tensorboard-dir "$TENSORBOARD_LOGS_PATH"
	--ckpt-format torch_dist
	--ckpt-fully-parallel-load
	--use-persistent-ckpt-worker
	--ckpt-assume-constant-structure
)

mkdir -p "$CHECKPOINT_PATH"
mkdir -p "$TENSORBOARD_LOGS_PATH"
mkdir -p "$DATA_CACHE_DIR"

srun --container-mounts="$TOPO_FILE:$TOPO_FILE,$STAGE_PATH:$STAGE_PATH,$DATA_PATH:$DATA_PATH,$WORK_DIR:$WORK_DIR,$VOCAB_FILE:$VOCAB_FILE,$MERGE_FILE:$MERGE_FILE,$CHECKPOINT_PATH:$CHECKPOINT_PATH,/var/tmp:/var/tmp,/opt/microsoft:/opt/microsoft" \
	--container-env=CUDA_DEVICE_MAX_CONNECTIONS,NCCL_TOPO_FILE,LOGLEVEL \
	--container-image=$SQUASHED_PYTORCH_IMAGE \
	torchrun "${DISTRIBUTED_ARGS[@]}" $WORK_DIR/pretrain_gpt.py \
	"${GPT_MODEL_ARGS[@]}" \
	"${TRAINING_ARGS[@]}" \
	"${MODEL_PARALLEL_ARGS[@]}" \
	"${DATA_ARGS[@]}" \
	"${EVAL_AND_LOGGING_ARGS[@]}"
