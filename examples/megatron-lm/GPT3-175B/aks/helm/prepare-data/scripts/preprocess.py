import os
import subprocess
import argparse
import logging
import time
import requests
from glob import glob

# Configuration constants
REQUEST_TIMEOUT = 30  # 30 seconds timeout for BPE file downloads
DOWNLOAD_RETRIES = 3
BACKOFF_TIME = 5

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],
)

def download_file(url, filepath, retry=DOWNLOAD_RETRIES):
    """Download a file from URL to filepath with retry logic."""
    logging.info(f"Downloading {url} to {filepath}")
    
    try:
        response = requests.get(url, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
        
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        with open(filepath, 'wb') as f:
            f.write(response.content)
        logging.info(f"Downloaded {filepath}")
        
    except requests.exceptions.Timeout:
        if retry > 0:
            time.sleep(BACKOFF_TIME)
            logging.warning(f"Timeout downloading {filepath}. Retrying ({retry} attempts left)...")
            download_file(url, filepath, retry=retry - 1)
        else:
            logging.error(f"Timeout downloading {filepath} after {DOWNLOAD_RETRIES} retries")
            raise
    except requests.exceptions.HTTPError as e:
        if retry > 0 and e.response.status_code in [429, 500, 502, 503, 504]:
            time.sleep(BACKOFF_TIME)
            logging.warning(f"HTTP {e.response.status_code} downloading {filepath}. Retrying ({retry} attempts left)...")
            download_file(url, filepath, retry=retry - 1)
        else:
            logging.error(f"HTTP error downloading {filepath}: {e}")
            raise
    except requests.exceptions.RequestException as e:
        if retry > 0:
            time.sleep(BACKOFF_TIME)
            logging.warning(f"Network error downloading {filepath}: {str(e)}. Retrying ({retry} attempts left)...")
            download_file(url, filepath, retry=retry - 1)
        else:
            logging.error(f"Network error downloading {filepath} after {DOWNLOAD_RETRIES} retries: {str(e)}")
            raise

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

def preprocess(input_directory="", output_directory="", worker_index=0, total_workers=1, worker_threads=None):
    logging.info(f"Input directory: {input_directory}")
    logging.info(f"Output directory: {output_directory}")
    
    # Create output directory if it doesn't exist
    os.makedirs(output_directory, exist_ok=True)
    
    # Create BPE directory one level above (in the main dataset directory)
    # e.g., if output_directory is /shared-data/slimpajama/preprocessed
    # then bpe_dir should be /shared-data/slimpajama/bpe
    dataset_dir = os.path.dirname(output_directory)
    bpe_dir = os.path.join(dataset_dir, "bpe")
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

    # Calculate number of worker threads for preprocessing
    # Use provided worker_threads, or default to reasonable number based on available CPUs
    if worker_threads is None:
        try:
            import multiprocessing
            # Use 80% of available CPUs, minimum 1, maximum 128
            worker_threads = max(1, min(128, int(multiprocessing.cpu_count() * 0.8)))
        except:
            # Fallback if multiprocessing is not available
            worker_threads = 16
    
    logging.info(f"Using {worker_threads} worker threads for preprocessing")

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
            f"--workers {worker_threads}"
        )
        logging.info(f"Running preprocessing for shard {shard_num} with {worker_threads} workers")
        subprocess.run([command], shell=True)
        shards_processed += 1
    
    # Create completion marker file in output directory
    completion_file = os.path.join(output_directory, f".preprocess-{worker_index}-complete")
    with open(completion_file, "w") as f:
        f.write(f"Worker {worker_index} completed preprocessing {shards_processed} shards")
    logging.info(f"Created completion marker: {completion_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Preprocess JSONL files for Megatron")
    parser.add_argument("--input-directory", type=str, required=True, help="Directory containing input files")
    parser.add_argument("--output-directory", type=str, required=True, help="Directory to write preprocessed files")
    parser.add_argument("--worker-index", type=int, default=0, help="Worker index")
    parser.add_argument("--total-workers", type=int, default=1, help="Total workers")
    parser.add_argument("--worker-threads", type=int, default=None, help="Number of worker threads for preprocessing (default: auto-detect based on CPU count)")
        
    args = parser.parse_args()

    # Handle backward compatibility
    input_dir = args.input_directory
    output_dir = args.output_directory
    
    preprocess(input_dir, output_dir, args.worker_index, args.total_workers, args.worker_threads)
