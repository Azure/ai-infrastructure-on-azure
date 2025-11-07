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
REQUEST_TIMEOUT = 300  # 5 minutes timeout for large file downloads

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

    try:
        response = requests.get(url, timeout=REQUEST_TIMEOUT)

        if response.status_code == 429 and retry > 0:
            time.sleep(BACKOFF_TIME)
            logging.warning("Throttled. Retrying download for %s...", filename)
            download_shard(url, filename, retry=retry - 1)
            return

        if response.status_code != 200:
            if retry > 0:
                time.sleep(BACKOFF_TIME)
                logging.warning(
                    "HTTP %s for %s. Retrying (%d attempts left)...",
                    response.status_code,
                    filename,
                    retry,
                )
                download_shard(url, filename, retry=retry - 1)
                return
            else:
                logging.error(
                    "Failed to download %s: HTTP %s", url, response.status_code
                )
                return

        with open(filename, "wb") as fn:
            fn.write(response.content)
        logging.info("Downloaded %s", filename)

    except requests.exceptions.Timeout:
        if retry > 0:
            time.sleep(BACKOFF_TIME)
            logging.warning(
                "Timeout downloading %s. Retrying (%d attempts left)...",
                filename,
                retry,
            )
            download_shard(url, filename, retry=retry - 1)
        else:
            logging.error("Timeout downloading %s after %d retries", filename, RETRIES)
    except requests.exceptions.RequestException as e:
        if retry > 0:
            time.sleep(BACKOFF_TIME)
            logging.warning(
                "Network error downloading %s: %s. Retrying (%d attempts left)...",
                filename,
                str(e),
                retry,
            )
            download_shard(url, filename, retry=retry - 1)
        else:
            logging.error(
                "Network error downloading %s after %d retries: %s",
                filename,
                RETRIES,
                str(e),
            )


def download(
    directory, full_dataset=True, sample_files=100, worker_index=0, total_workers=1
):
    """Download SlimPajama dataset from Hugging Face with parallel worker support."""
    files_downloaded = 0
    files_to_process = []

    # First, calculate all files that need to be downloaded
    for chunk in range(1, CHUNKS + 1):
        shard_limit = (
            SHARDS if full_dataset else min(sample_files // CHUNKS + 1, SHARDS)
        )
        for shard in range(0, shard_limit):
            if not full_dataset and len(files_to_process) >= sample_files:
                break

            filename = f"example_train_chunk{chunk}_shard{shard}.jsonl.zst"
            url = f"{REPOSITORY_PATH}/chunk{chunk}/example_train_{shard}.jsonl.zst"
            files_to_process.append((filename, url))

        if not full_dataset and len(files_to_process) >= sample_files:
            break

    # Limit to sample_files if not downloading full dataset
    if not full_dataset:
        files_to_process = files_to_process[:sample_files]

    # Distribute files across workers using modulo
    worker_files = [
        file_info
        for i, file_info in enumerate(files_to_process)
        if i % total_workers == worker_index
    ]

    logging.info(
        f"Worker {worker_index}/{total_workers}: Processing {len(worker_files)} files out of {len(files_to_process)} total files"
    )

    # Download assigned files
    for filename, url in worker_files:
        full_filename = os.path.join(directory, filename)
        download_shard(url, full_filename)
        files_downloaded += 1

    logging.info(
        f"Worker {worker_index} completed: Downloaded {files_downloaded} files"
    )

    # Create completion marker file
    completion_file = os.path.join(directory, f".download-{worker_index}-complete")
    with open(completion_file, "w") as f:
        f.write(f"Worker {worker_index} completed downloading {files_downloaded} files")
    logging.info(f"Created completion marker: {completion_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Download SlimPajama from Hugging Face with parallel worker support."
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
    parser.add_argument(
        "--worker-index",
        type=int,
        default=0,
        help="Index of this worker (0-based).",
    )
    parser.add_argument(
        "--total-workers",
        type=int,
        default=1,
        help="Total number of workers.",
    )
    args = parser.parse_args()

    os.makedirs(args.directory, exist_ok=True)
    download(
        args.directory,
        args.full_dataset,
        args.sample_files,
        args.worker_index,
        args.total_workers,
    )
