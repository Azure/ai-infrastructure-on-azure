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

def extract_shard(shard, output_directory):
    extracted_filename = os.path.join(output_directory, os.path.basename(shard).replace(".zst", ""))

    # Very rare scenario where another rank has already processed a shard
    if not os.path.exists(shard):
        logging.info(f"Skipping {shard} - file no longer exists (likely processed by another worker)")
        return False

    # Check if already extracted
    if os.path.exists(extracted_filename):
        logging.info(f"Skipping {shard} - already extracted to {extracted_filename}")
        return True

    try:
        # Ensure output directory exists
        os.makedirs(output_directory, exist_ok=True)
        
        with open(shard, "rb") as in_file, open(extracted_filename, "wb") as out_file:
            dctx = zstd.ZstdDecompressor(max_window_size=2**27)
            reader = dctx.stream_reader(in_file)

            while True:
                chunk = reader.read(4096)
                if not chunk:
                    break
                out_file.write(chunk)

        logging.info(f"Extracted {shard} to {extracted_filename}")
        return True
        
    except Exception as e:
        logging.error(f"Error processing {shard}: {e}")
        # Clean up partial extraction if it exists
        try:
            if os.path.exists(extracted_filename):
                os.remove(extracted_filename)
                logging.info(f"Cleaned up partial extraction {extracted_filename}")
        except OSError:
            pass
        return False

def extract(input_directory="", output_directory="", worker_index=0, total_workers=1):
    dataset = sorted(glob(os.path.join(input_directory, "example_train*zst")))
    shards_to_extract = split_shards(total_workers, dataset)

    logging.info(f"Worker {worker_index}/{total_workers}: Assigned {len(shards_to_extract[worker_index])} files")
    logging.info(f"Input directory: {input_directory}")
    logging.info(f"Output directory: {output_directory}")
    
    processed_count = 0
    skipped_count = 0
    
    for shard in shards_to_extract[worker_index]:
        result = extract_shard(shard, output_directory)
        if result:
            processed_count += 1
        else:
            skipped_count += 1
    
    logging.info(f"Worker {worker_index}: Processed {processed_count} files, skipped {skipped_count} files")
    
    # Create completion marker file in the output directory
    os.makedirs(output_directory, exist_ok=True)
    completion_file = os.path.join(output_directory, f".extract-{worker_index}-complete")
    with open(completion_file, "w") as f:
        f.write(f"Worker {worker_index} completed: processed {processed_count} files, skipped {skipped_count} files")
    logging.info(f"Created completion marker: {completion_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract zst files")
    parser.add_argument("--input-directory", type=str, required=True, help="Directory containing input files")
    parser.add_argument("--output-directory", type=str, required=True, help="Directory to write extracted files")
    parser.add_argument("--worker-index", type=int, default=0, help="Worker index")
    parser.add_argument("--total-workers", type=int, default=1, help="Total workers")
    
    args = parser.parse_args()

    # Handle backward compatibility
    input_dir = args.input_directory
    output_dir = args.output_directory

    extract(input_dir, output_dir, args.worker_index, args.total_workers)
