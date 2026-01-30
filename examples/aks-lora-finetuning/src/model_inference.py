#!/usr/bin/env python3
"""Side-by-side comparison inference for GPT-OSS-20B (Fine-tuned vs Baseline)"""

import os
import sys
import logging
from pathlib import Path
from typing import Dict
import threading

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel
from azure.storage.blob import BlobServiceClient
from azure.identity import DefaultAzureCredential

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

# Config
STORAGE_ACCOUNT = os.getenv("STORAGE_ACCOUNT_NAME")
MODEL_CONTAINER = os.getenv("MODEL_CONTAINER", "models")
MODEL_PATH = os.getenv("MODEL_PATH", "gpt-oss-20b-multilingual")
BASE_MODEL = os.getenv("BASE_MODEL", "openai/gpt-oss-20b")
LOCAL_DIR = "/workspace/finetuned-model"


class ComparisonInference:
    """Side-by-side inference for fine-tuned vs baseline models (2 GPUs)"""
    
    def __init__(self):
        """Initialize both models on separate GPUs"""
        self.finetuned_model = None
        self.baseline_model = None
        self.tokenizer = None
        self.num_gpus = 0
        
        self._check_gpu()
        self._load_models()
    
    def _check_gpu(self):
        """Verify 2 GPUs available"""
        if not torch.cuda.is_available():
            logger.error("No GPU available!")
            sys.exit(1)
        
        self.num_gpus = torch.cuda.device_count()
        if self.num_gpus < 2:
            logger.error(f"Comparison mode requires 2 GPUs (found {self.num_gpus})")
            sys.exit(1)
        
        logger.info(f"Found {self.num_gpus} GPUs")
        for i in range(self.num_gpus):
            name = torch.cuda.get_device_name(i)
            mem = torch.cuda.get_device_properties(i).total_memory / 1024**3
            logger.info(f"  GPU {i}: {name} ({mem:.1f} GB)")
    
    def _download_finetuned_model(self) -> str:
        """Download fine-tuned model from Azure Blob Storage"""
        logger.info("Downloading fine-tuned model from Azure...")
        
        client = BlobServiceClient(
            account_url=f"https://{STORAGE_ACCOUNT}.blob.core.windows.net",
            credential=DefaultAzureCredential()
        )
        
        container = client.get_container_client(MODEL_CONTAINER)
        Path(LOCAL_DIR).mkdir(parents=True, exist_ok=True)
        
        count = 0
        for blob in container.list_blobs(name_starts_with=MODEL_PATH):
            rel_path = blob.name[len(MODEL_PATH):].lstrip('/')
            if not rel_path:
                continue
            
            local_path = Path(LOCAL_DIR) / rel_path
            local_path.parent.mkdir(parents=True, exist_ok=True)
            
            with open(local_path, 'wb') as f:
                f.write(container.get_blob_client(blob.name).download_blob().readall())
            count += 1
        
        logger.info(f"Downloaded {count} files")
        return LOCAL_DIR
    
    def _load_models(self):
        """Load both models on separate GPUs for parallel inference"""
        logger.info("Loading models on separate GPUs...")
        
        # Shared tokenizer
        self.tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL)
        
        # Load fine-tuned on GPU 0
        logger.info("Loading fine-tuned model on GPU 0...")
        finetuned_path = self._download_finetuned_model()
        base_model = AutoModelForCausalLM.from_pretrained(
            BASE_MODEL,
            attn_implementation="eager",
            torch_dtype="auto",
            use_cache=True,
            device_map=None
        )
        self.finetuned_model = PeftModel.from_pretrained(base_model, finetuned_path).merge_and_unload()
        self.finetuned_model = self.finetuned_model.to("cuda:0")
        self.finetuned_model.eval()
        logger.info("✓ Fine-tuned model ready on GPU 0")
        
        # Load baseline on GPU 1
        logger.info("Loading baseline model on GPU 1...")
        self.baseline_model = AutoModelForCausalLM.from_pretrained(
            BASE_MODEL,
            attn_implementation="eager",
            torch_dtype="auto",
            use_cache=True,
            device_map=None
        )
        self.baseline_model = self.baseline_model.to("cuda:1")
        self.baseline_model.eval()
        logger.info("✓ Baseline model ready on GPU 1")
        
        # Log memory usage
        for i in range(2):
            alloc = torch.cuda.memory_allocated(i) / 1024**3
            logger.info(f"GPU {i}: {alloc:.1f} GB allocated")
    
    def generate(self, prompt: str, reasoning_language: str = "English", 
                 model: str = "finetuned", max_new_tokens: int = 512) -> str:
        """Generate response from specified model (finetuned or baseline)"""
        active = self.finetuned_model if model == "finetuned" else self.baseline_model
        
        # Prepare prompt
        messages = [
            {"role": "system", "content": f"reasoning language: {reasoning_language}"},
            {"role": "user", "content": prompt}
        ]
        
        # apply_chat_template returns BatchEncoding with input_ids
        tokenized = self.tokenizer.apply_chat_template(
            messages, add_generation_prompt=True, return_tensors="pt"
        )
        input_ids = tokenized.input_ids.to(active.device)
        
        # Generate
        with torch.no_grad():
            output = active.generate(
                input_ids, 
                max_new_tokens=max_new_tokens,
                do_sample=True,
                temperature=0.6
            )
        
        # Decode only generated tokens
        generated_tokens = output[0][input_ids.shape[-1]:]
        return self.tokenizer.decode(generated_tokens, skip_special_tokens=False)
    
    def compare(self, prompt: str, reasoning_language: str = "English", 
                max_new_tokens: int = 512) -> Dict[str, str]:
        """Compare both models in parallel (2 GPUs)"""
        logger.info("Parallel comparison on 2 GPUs...")
        
        results = {}
        errors = {}
        
        def run(model_name):
            try:
                results[model_name] = self.generate(prompt, reasoning_language, model_name, max_new_tokens)
            except Exception as e:
                errors[model_name] = str(e)
                logger.error(f"{model_name} error: {e}")
        
        # Run in parallel
        threads = [threading.Thread(target=run, args=(m,)) for m in ["finetuned", "baseline"]]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        
        if errors:
            raise RuntimeError(f"Inference errors: {errors}")
        
        return results


# Expose for web UI
inference = None

def get_inference():
    """Get or create inference instance"""
    global inference
    if inference is None:
        inference = ComparisonInference()
    return inference


if __name__ == "__main__":
    """Direct usage: load models and wait"""
    logger.info("Initializing comparison inference...")
    inf = ComparisonInference()
    logger.info("Models ready. Use as module: from model_inference import get_inference")
    
    # Keep alive
    import time
    while True:
        time.sleep(60)
