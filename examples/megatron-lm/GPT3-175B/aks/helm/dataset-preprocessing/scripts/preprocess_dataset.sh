#!/bin/bash
set -euo pipefail

echo "Starting dataset preprocessing..."

INPUT_DIR="$1"
OUTPUT_DIR="$2"
VOCAB_DIR="$3"
WORKERS="$4"

echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Vocab directory: $VOCAB_DIR"

# Create output and vocab directories
mkdir -p "$OUTPUT_DIR" "$VOCAB_DIR"

# Download GPT-2 BPE vocabulary files if they don't exist
if [ ! -f "$VOCAB_DIR/vocab.json" ]; then
  echo "Downloading GPT-2 BPE vocabulary..."
  wget -O "$VOCAB_DIR/vocab.json" https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-vocab.json
  wget -O "$VOCAB_DIR/merges.txt" https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-merges.txt
fi

# Find all training files
TRAIN_FILES=$(find "$INPUT_DIR" -name "train_*.jsonl" -type f | sort | tr '\n' ' ')

if [ -z "$TRAIN_FILES" ]; then
  echo "No train_*.jsonl files found. Please run concatenation first."
  exit 1
fi

echo "Found training files: $(echo $TRAIN_FILES | wc -w)"

# Run Megatron preprocessing
python /megatron-lm/tools/preprocess_data.py \
  --input $TRAIN_FILES \
  --output-prefix "$OUTPUT_DIR/slimpajama" \
  --vocab-file "$VOCAB_DIR/vocab.json" \
  --merge-file "$VOCAB_DIR/merges.txt" \
  --tokenizer-type GPT2BPETokenizer \
  --dataset-impl mmap \
  --append-eod \
  --workers "$WORKERS"

echo "Preprocessing completed!"
echo "Output files:"
ls -la "$OUTPUT_DIR"/

echo "Binary files created:"
find "$OUTPUT_DIR" -name "*.bin" -type f | wc -l

echo "Index files created:"
find "$OUTPUT_DIR" -name "*.idx" -type f | wc -l
