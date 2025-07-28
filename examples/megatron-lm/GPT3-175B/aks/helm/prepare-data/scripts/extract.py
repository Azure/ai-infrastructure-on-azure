import os
import argparse
import logging
from glob import glob
import zstandard as zstd

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],
)

def split_shards(wsize, dataset):
    shards = []

    for shard in range(wsize):
        idx_start = (shard * len(dataset)) // wsize
        idx_end = ((shard + 1) * len(dataset)) // wsize
        shards.append(dataset[idx_start:idx_end])
    return shards

def extract_shard(shard):
    extracted_filename = shard.replace(".zst", "")

    # Very rare scenario where another rank has already processed a shard
    if not os.path.exists(shard):
        return

    with open(shard, "rb") as in_file, open(extracted_filename, "wb") as out_file:
        dctx = zstd.ZstdDecompressor(max_window_size=2**27)
        reader = dctx.stream_reader(in_file)

        while True:
            chunk = reader.read(4096)
            if not chunk:
                break
            out_file.write(chunk)

    os.remove(shard)
    logging.info(f"Extracted and removed {shard}")

def extract(directory="", worker_index=0, total_workers=1):
    dataset = sorted(glob(os.path.join(directory, "example_train*zst")))
    shards_to_extract = split_shards(total_workers, dataset)

    logging.info(f"Worker {worker_index}/{total_workers}: Processing {len(shards_to_extract[worker_index])} files")

    for shard in shards_to_extract[worker_index]:
        extract_shard(shard)
    
    # Create completion marker file
    completion_file = os.path.join(directory, f".extract-{worker_index}-complete")
    with open(completion_file, "w") as f:
        f.write(f"Worker {worker_index} completed extracting {len(shards_to_extract[worker_index])} files")
    logging.info(f"Created completion marker: {completion_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract zst files")
    parser.add_argument("--directory", type=str, required=True, help="Directory containing files")
    parser.add_argument("--worker-index", type=int, default=0, help="Worker index")
    parser.add_argument("--total-workers", type=int, default=1, help="Total workers")
    args = parser.parse_args()

    extract(args.directory, args.worker_index, args.total_workers)
