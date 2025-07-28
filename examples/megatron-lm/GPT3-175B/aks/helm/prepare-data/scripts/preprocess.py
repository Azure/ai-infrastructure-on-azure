import os
import subprocess
import argparse
import logging
import time
import requests
from glob import glob

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],
)

def download_file(url, filepath):
    """Download a file from URL to filepath."""
    logging.info(f"Downloading {url} to {filepath}")
    response = requests.get(url)
    response.raise_for_status()
    
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, 'wb') as f:
        f.write(response.content)
    logging.info(f"Downloaded {filepath}")

def wait_for_files(filepaths, timeout=300):
    """Wait for files to exist, with timeout."""
    start_time = time.time()
    while time.time() - start_time < timeout:
        if all(os.path.exists(fp) for fp in filepaths):
            logging.info("All required files are available")
            return True
        logging.info("Waiting for files to be available...")
        time.sleep(10)
    
    raise TimeoutError(f"Timeout waiting for files: {filepaths}")

def split_shards(wsize, dataset):
    shards = []

    for shard in range(wsize):
        idx_start = (shard * len(dataset)) // wsize
        idx_end = ((shard + 1) * len(dataset)) // wsize
        shards.append(dataset[idx_start:idx_end])
    return shards

def preprocess(input_directory="", output_directory="", worker_index=0, total_workers=1):
    logging.info(f"Input directory: {input_directory}")
    logging.info(f"Output directory: {output_directory}")
    
    # Create output directory if it doesn't exist
    os.makedirs(output_directory, exist_ok=True)
    
    # Create BPE directory in output directory and download files on rank 0
    bpe_dir = os.path.join(output_directory, "bpe")
    vocab_file = os.path.join(bpe_dir, "vocab.json")
    merges_file = os.path.join(bpe_dir, "merges.txt")
    
    download_vocab_url = "https://huggingface.co/gpt2/resolve/main/vocab.json"
    download_merges_url = "https://huggingface.co/gpt2/resolve/main/merges.txt"
    
    if worker_index == 0:
        # Download BPE files
        download_file(download_vocab_url, vocab_file)
        download_file(download_merges_url, merges_file)
        
        # Create completion marker
        completion_file = os.path.join(bpe_dir, ".download_complete")
        with open(completion_file, 'w') as f:
            f.write("BPE files downloaded")
        logging.info("BPE files download completed")
    else:
        # Wait for rank 0 to complete downloads
        completion_file = os.path.join(bpe_dir, ".download_complete")
        logging.info(f"Worker {worker_index} waiting for BPE files...")
        wait_for_files([completion_file])
    
    dataset = sorted(glob(os.path.join(input_directory, "slim_pajama*jsonl")))
    logging.info(f"Found {len(dataset)} files to preprocess")
    shards_to_extract = split_shards(total_workers, dataset)

    shards_processed = 0
    for num, shard in enumerate(shards_to_extract[worker_index]):
        shard_num = worker_index + (num * total_workers)  # Counter for which file is processed
        output_path = os.path.join(output_directory, f"llama-slim-pajama-{shard_num}")
        command = (
            "python3 /opt/NeMo/scripts/nlp_language_modeling/preprocess_data_for_megatron.py "
            f"--input {shard} "
            f"--output-prefix {output_path} "
            f"--dataset-impl mmap "
            f"--tokenizer-type GPT2BPETokenizer "
            f"--tokenizer-library megatron "
            f"--vocab-file {vocab_file} "
            f"--merge-file {merges_file} "
            f"--workers 80"
        )
        logging.info(f"Running preprocessing for shard {shard_num}")
        subprocess.run([command], shell=True)
        shards_processed += 1
    
    # Create completion marker file in output directory
    completion_file = os.path.join(output_directory, f".preprocess-{worker_index}-complete")
    with open(completion_file, "w") as f:
        f.write(f"Worker {worker_index} completed preprocessing {shards_processed} shards")
    logging.info(f"Created completion marker: {completion_file}")
    with open(completion_file, "w") as f:
        f.write(f"Worker {worker_index} completed preprocessing {shards_processed} shards")
    logging.info(f"Created completion marker: {completion_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Preprocess JSONL files for Megatron")
    parser.add_argument("--input-directory", type=str, required=True, help="Directory containing input files")
    parser.add_argument("--output-directory", type=str, required=True, help="Directory to write preprocessed files")
    parser.add_argument("--worker-index", type=int, default=0, help="Worker index")
    parser.add_argument("--total-workers", type=int, default=1, help="Total workers")
        
    args = parser.parse_args()

    # Handle backward compatibility
    input_dir = args.input_directory
    output_dir = args.output_directory
    
    preprocess(input_dir, output_dir, args.worker_index, args.total_workers)
