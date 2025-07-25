#!/bin/bash
set -xe

# Parse arguments
STORAGE_MOUNT="$1"
DATASET_PATH="$2"
LOGS_PATH="$3"
CHECKPOINT_PATH="$4"
CHUNKS="$5"
GLOBAL_BATCH_SIZE="$6"
ITERATIONS="$7"
SAVE_INTERVAL="$8"
EVAL_INTERVAL="$9"
GPUS_PER_NODE="${10}"
NODES="${11}"
USE_SHARP="${12}"
LOG_LEVEL="${13}"
TOPO_FILE="${14}"

# Export model configuration variables (will be set by helm template)
# NUM_LAYERS, HIDDEN_SIZE, NUM_ATTENTION_HEADS, SEQ_LENGTH, 
# TENSOR_MODEL_PARALLEL_SIZE, PIPELINE_MODEL_PARALLEL_SIZE

export OMPI_MCA_coll_hcoll_enable=0
export CUDA_DEVICE_ORDER=PCI_BUS_ID
export NCCL_SOCKET_IFNAME=eth0
export UCX_TLS=rc
export UCX_NET_DEVICES=mlx5_ib0:1
export NCCL_DEBUG="$LOG_LEVEL"
export NCCL_IB_PCI_RELAXED_ORDERING=1
export NCCL_IB_QPS_PER_CONNECTION=4
export NCCL_IGNORE_CPU_AFFINITY=1
export NCCL_P2P_NET_CHUNKSIZE=$((512 * 1024))
export NCCL_PXN_DISABLE=1
export NCCL_MIN_NCHANNELS=32
export NCCL_TOPO_FILE="$TOPO_FILE"
export CUDA_DEVICE_MAX_CONNECTIONS=1

if [ "$USE_SHARP" -eq 1 ]; then
  export SHARP_SMX_UCX_INTERFACE=mlx5_ib0:1
  export SHARP_COLL_ENABLE_SAT=1
  export SHARP_COLL_LOG_LEVEL=3
  export SHARP_COLL_ENABLE_PCI_RELAXED_ORDERING=1
  export NCCL_COLLNET_ENABLE=1
fi

# Paths
DATA_PATH="$STORAGE_MOUNT/$DATASET_PATH"
TENSORBOARD_LOGS_PATH="$STORAGE_MOUNT/$LOGS_PATH"
CHECKPOINT_PATH="$STORAGE_MOUNT/$CHECKPOINT_PATH"
VOCAB_FILE="$STORAGE_MOUNT/slimpajama/bpe/vocab.json"
MERGE_FILE="$STORAGE_MOUNT/slimpajama/bpe/merges.txt"
DATA_CACHE_DIR="$STORAGE_MOUNT/datacache"

# Create directories
mkdir -p "$TENSORBOARD_LOGS_PATH" "$CHECKPOINT_PATH" "$DATA_CACHE_DIR"

# Generate data file lists
DATA_SET_SIZE=$(find $DATA_PATH -name "*.bin" -type f | wc -l)

echo "Found $DATA_SET_SIZE dataset files"

# Calculate train/validation/test splits
TRAIN_FILES=$(($DATA_SET_SIZE - $CHUNKS - $CHUNKS))

echo "Using $TRAIN_FILES files for training, $CHUNKS for validation, $CHUNKS for test"

# Generate training data paths
TRAIN_DATA=$(find $DATA_PATH -name "*.bin" -type f | sort | head -n $TRAIN_FILES | sed 's/.bin//g' | awk '{print "1.0 " $0}' | tr '\n' ' ')
VALID_DATA=$(find $DATA_PATH -name "*.bin" -type f | sort | tail -n $CHUNKS | sed 's/.bin//g' | awk '{print "1.0 " $0}' | tr '\n' ' ')
TEST_DATA=$(find $DATA_PATH -name "*.bin" -type f | sort | tail -n $(($CHUNKS + $CHUNKS)) | head -n $CHUNKS | sed 's/.bin//g' | awk '{print "1.0 " $0}' | tr '\n' ' ')

# Debug environment
echo "Environment variables:"
env | grep -E "(RANK|MASTER|WORLD|NCCL|CUDA)" | sort

echo "Starting Megatron-LM training..."
echo "Model configuration: $NUM_LAYERS layers, $HIDDEN_SIZE hidden size, $NUM_ATTENTION_HEADS heads"
echo "Parallelism: TP=$TENSOR_MODEL_PARALLEL_SIZE, PP=$PIPELINE_MODEL_PARALLEL_SIZE"

# Build SHARP argument
SHARP_ARG=""
if [ "$USE_SHARP" -eq 1 ]; then
  SHARP_ARG="--use-sharp"
fi

# Run training
torchrun \
  --nproc_per_node "$GPUS_PER_NODE" \
  --nnodes "$NODES" \
  --rdzv_id $RANDOM \
  --rdzv_backend c10d \
  --rdzv_endpoint "$MASTER_ADDR:$MASTER_PORT" \
  /megatron-lm/pretrain_gpt.py \
  --num-layers $NUM_LAYERS \
  --hidden-size $HIDDEN_SIZE \
  --num-attention-heads $NUM_ATTENTION_HEADS \
  --seq-length $SEQ_LENGTH \
  --max-position-embeddings 2048 \
  --attention-backend auto \
  --micro-batch-size 1 \
  --global-batch-size "$GLOBAL_BATCH_SIZE" \
  --train-iters "$ITERATIONS" \
  --lr-decay-iters "$ITERATIONS" \
  --save "$CHECKPOINT_PATH" \
  --load "$CHECKPOINT_PATH" \
  --data-path $TRAIN_DATA \
  --valid-data-path $VALID_DATA \
  --test-data-path $TEST_DATA \
  --data-cache-path "$DATA_CACHE_DIR" \
  --vocab-file "$VOCAB_FILE" \
  --merge-file "$MERGE_FILE" \
  --tokenizer-type GPT2BPETokenizer \
  --split 949,50,1 \
  --distributed-backend nccl \
  --lr 0.00015 \
  --lr-decay-style cosine \
  --min-lr 1.0e-5 \
  --weight-decay 1e-2 \
  --clip-grad 1.0 \
  --lr-warmup-fraction .01 \
  --checkpoint-activations \
  --log-interval 100 \
  --save-interval "$SAVE_INTERVAL" \
  --eval-interval "$EVAL_INTERVAL" \
  --eval-iters 10 \
  --fp16 \
  --tensorboard-dir "$TENSORBOARD_LOGS_PATH" \
  --tensorboard-queue-size 5 \
  --log-timers-to-tensorboard \
  --log-batch-size-to-tensorboard \
  --log-validation-ppl-to-tensorboard \
  --tensor-model-parallel-size $TENSOR_MODEL_PARALLEL_SIZE \
  --pipeline-model-parallel-size $PIPELINE_MODEL_PARALLEL_SIZE \
  $SHARP_ARG \
  --use-distributed-optimizer
