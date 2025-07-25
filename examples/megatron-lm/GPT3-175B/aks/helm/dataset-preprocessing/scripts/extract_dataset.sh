#!/bin/bash
set -euo pipefail

echo "Starting dataset extraction..."

INPUT_DIR="$1"
WORKERS="$2"

echo "Input directory: $INPUT_DIR"
echo "Processing .zst files with $WORKERS workers..."

# Find all .zst files and extract them in parallel
find "$INPUT_DIR" -name "*.zst" -type f | \
parallel -j "$WORKERS" \
  'echo "Extracting {}"; zstd -d "{}" --rm && echo "Completed {}"'

echo "Extraction completed!"
echo "Extracted files count:"
find "$INPUT_DIR" -name "*.jsonl" -type f | wc -l

echo "Total size after extraction:"
du -sh "$INPUT_DIR"
