"""
Modified from https://docs.nvidia.com/dgx-cloud/run-ai/latest/nemo-e2e-example.html
and from https://github.com/NVIDIA/NeMo-Framework-Launcher
Copyright (c) 2022, NVIDIA CORPORATION. All rights reserved.
This script downloads Slimpajama 627B dataset from Hugging Face.
"""
import os
import argparse
import time
import logging

import requests


CHUNKS = 10
SHARDS = 6000
REPOSITORY_PATH = "https://huggingface.co/datasets/cerebras/SlimPajama-627B/resolve/main/train"
BACKOFF_TIME = 10
RETRIES = 3

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.StreamHandler()
    ]
)


def download_shard(url, filename, retry=RETRIES):
    """Download a shard from the given URL and save it to the specified filename."""
    if os.path.exists(filename):
        logging.warning(f"File {filename} already exists. Skipping download.")
        return

    response = requests.get(url)

    if response.status_code == 429 and retry > 0:
        time.sleep(BACKOFF_TIME)
        logging.warning(f"Throttled. Retrying download for {filename}...")
        download_shard(url, filename, retry=retry - 1)

    if response.status_code != 200:
        return

    with open(filename, 'wb') as fn:
        fn.write(response.content)


def download(directory):
    """Download SlimPajama dataset from Hugging Face."""
    for chunk in range(1, CHUNKS + 1):
        for shard in range(0, SHARDS):
            filename = f'example_train_chunk{chunk}_shard{shard}.jsonl.zst'
            filename = os.path.join(directory, filename)
            url = f'{REPOSITORY_PATH}/chunk{chunk}/example_train_{shard}.jsonl.zst'
            download_shard(url, filename)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Download SlimPajama from Hugging Face.")
    parser.add_argument(
        "--directory",
        type=str,
        required=True,
        help="Directory to save downloaded files.",
    )
    args = parser.parse_args()

    os.makedirs(args.directory, exist_ok=True)
    download(args.directory)
