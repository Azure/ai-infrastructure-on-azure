import os
import argparse
import logging
from glob import glob

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],
)

def concatenate(input_directory="", output_directory="", worker_index=0, total_workers=1):
    shards_per_file = 1200
    files = sorted(glob(os.path.join(input_directory, "example_train_chunk*.jsonl")))
    num_files = len(files)
    
    logging.info(f"Input directory: {input_directory}")
    logging.info(f"Output directory: {output_directory}")
    logging.info(f"Found {num_files} files to process")
    
    # Find the ceiling of the result
    shards = ((num_files + shards_per_file - 1) // shards_per_file)
    
    logging.info(f"Creating {shards} combined chunk(s) comprising {shards_per_file} files each")
    
    # Ensure output directory exists
    os.makedirs(output_directory, exist_ok=True)
    
    chunks_processed = 0
    for i in range(shards):
        if ((i - worker_index) % total_workers) != 0:
            continue
            
        file_start = i * shards_per_file
        
        if ((i + 1) * shards_per_file) >= len(files):
            file_stop = len(files)
        else:
            file_stop = (i + 1) * shards_per_file
        
        logging.info(f"Building chunk {i} with files {file_start} to {file_stop}")
        
        output_file = os.path.join(output_directory, f"slim_pajama_{i}.jsonl")
        with open(output_file, "w") as outf:
            for file_idx in range(file_start, min(file_stop, len(files))):
                with open(files[file_idx], "r") as inf:
                    outf.write(inf.read())
               
        chunks_processed += 1
    
    # Create completion marker file in output directory
    completion_file = os.path.join(output_directory, f".concatenate-{worker_index}-complete")
    with open(completion_file, "w") as f:
        f.write(f"Worker {worker_index} completed concatenating {chunks_processed} chunks")
    logging.info(f"Created completion marker: {completion_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Concatenate JSONL files")
    parser.add_argument("--input-directory", type=str, required=True, help="Directory containing input files")
    parser.add_argument("--output-directory", type=str, required=True, help="Directory to write concatenated files")
    parser.add_argument("--worker-index", type=int, default=0, help="Worker index")
    parser.add_argument("--total-workers", type=int, default=1, help="Total workers")
    
    args = parser.parse_args()

    # Handle backward compatibility
    input_dir = args.input_directory
    output_dir = args.output_directory

    concatenate(input_dir, output_dir, args.worker_index, args.total_workers)
