"""
Modified from https://docs.nvidia.com/dgx-cloud/run-ai/latest/nemo-e2e-example.html
and from https://github.com/NVIDIA/NeMo-Framework-Launcher
Copyright (c) 2022, NVIDIA CORPORATION. All rights reserved.
This script downloads Slimpajama 627B dataset from Hugging Face.
"""

import argparse
import logging
import os
import time
import requests

CHUNKS = 10
SHARDS = 6000
REPOSITORY_PATH = (
    "https://huggingface.co/datasets/cerebras/SlimPajama-627B/resolve/main/train"
)
BACKOFF_TIME = 10
RETRIES = 3

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],
)

def download_shard(url, filename, retry=RETRIES):
    """Download a shard from the given URL and save it to the specified filename."""
    if os.path.exists(filename):
        logging.warning("File %s already exists. Skipping download.", filename)
        return

    response = requests.get(url)

    if response.status_code == 429 and retry > 0:
        time.sleep(BACKOFF_TIME)
        logging.warning("Throttled. Retrying download for %s...", filename)
        download_shard(url, filename, retry=retry - 1)

    if response.status_code != 200:
        logging.error("Failed to download %s: %s", url, response.status_code)
        return

    with open(filename, "wb") as fn:
        fn.write(response.content)
    logging.info("Downloaded %s", filename)

def download(directory, full_dataset=True, sample_files=100):
    """Download SlimPajama dataset from Hugging Face."""
    files_downloaded = 0
    for chunk in range(1, CHUNKS + 1):
        shard_limit = SHARDS if full_dataset else min(sample_files // CHUNKS + 1, SHARDS)
        for shard in range(0, shard_limit):
            if not full_dataset and files_downloaded >= sample_files:
                return
            
            filename = f"example_train_chunk{chunk}_shard{shard}.jsonl.zst"
            filename = os.path.join(directory, filename)
            url = f"{REPOSITORY_PATH}/chunk{chunk}/example_train_{shard}.jsonl.zst"
            download_shard(url, filename)
            files_downloaded += 1

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Download SlimPajama from Hugging Face."
    )
    parser.add_argument(
        "--directory",
        type=str,
        required=True,
        help="Directory to save downloaded files.",
    )
    parser.add_argument(
        "--full-dataset",
        action="store_true",
        help="Download full dataset.",
    )
    parser.add_argument(
        "--sample-files",
        type=int,
        default=100,
        help="Number of files to download for sample.",
    )
    args = parser.parse_args()

    os.makedirs(args.directory, exist_ok=True)
    download(args.directory, args.full_dataset, args.sample_files)
