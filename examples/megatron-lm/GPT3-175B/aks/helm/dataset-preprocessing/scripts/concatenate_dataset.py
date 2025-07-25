import os
import glob
import math
import multiprocessing as mp
import argparse

def concatenate_chunk(chunk_files, output_file):
    print(f"Concatenating {len(chunk_files)} files into {output_file}")
    with open(output_file, 'w') as outf:
        for file_path in chunk_files:
            try:
                with open(file_path, 'r') as inf:
                    outf.write(inf.read())
            except Exception as e:
                print(f"Error processing {file_path}: {e}")
    print(f"Completed {output_file}")

def main():
    parser = argparse.ArgumentParser(description="Concatenate JSONL files into training chunks")
    parser.add_argument("--input-dir", required=True, help="Directory containing JSONL files")
    parser.add_argument("--target-files", type=int, default=72, help="Number of target files")
    parser.add_argument("--workers", type=int, default=16, help="Number of parallel workers")
    
    args = parser.parse_args()
    
    input_dir = args.input_dir
    target_files = args.target_files
    workers = args.workers
    
    # Find all extracted jsonl files
    jsonl_files = sorted(glob.glob(os.path.join(input_dir, "*.jsonl")))
    print(f"Found {len(jsonl_files)} files to concatenate")
    
    if len(jsonl_files) == 0:
        print("No .jsonl files found. Please run extraction first.")
        return
    
    # Calculate files per chunk
    files_per_chunk = math.ceil(len(jsonl_files) / target_files)
    print(f"Files per chunk: {files_per_chunk}")
    
    # Create chunks
    chunks = []
    for i in range(0, len(jsonl_files), files_per_chunk):
        chunk_files = jsonl_files[i:i + files_per_chunk]
        output_file = os.path.join(input_dir, f"train_{len(chunks):05d}.jsonl")
        chunks.append((chunk_files, output_file))
    
    print(f"Created {len(chunks)} chunks")
    
    # Process chunks in parallel
    pool = mp.Pool(workers)
    pool.starmap(concatenate_chunk, chunks)
    pool.close()
    pool.join()
    
    print("Concatenation completed!")
    print(f"Created {len(chunks)} training files")

if __name__ == "__main__":
    main()
