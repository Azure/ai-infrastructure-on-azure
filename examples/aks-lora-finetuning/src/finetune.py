#!/usr/bin/env python3
"""
Fine-tuning script for OpenAI gpt-oss-20b on AKS with GPU
Uses LoRA for parameter-efficient fine-tuning with Mxfp4 quantization
Integrates with Azure Blob Storage for model saving
"""

import logging
import os
import sys

# Enable PyTorch CUDA memory optimization
os.environ["PYTORCH_CUDA_ALLOC_CONF"] = "expandable_segments:True"

import torch
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from datasets import load_dataset
from peft import LoraConfig, get_peft_model
from transformers import AutoModelForCausalLM, AutoTokenizer, Mxfp4Config
from trl import SFTConfig, SFTTrainer

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)

# Configuration
MODEL_NAME = "openai/gpt-oss-20b"
DATASET_NAME = "HuggingFaceH4/Multilingual-Thinking"
STORAGE_ACCOUNT_NAME = os.getenv("STORAGE_ACCOUNT_NAME")
MODEL_CONTAINER = os.getenv("MODEL_CONTAINER", "models")
OUTPUT_DIR = "/workspace/output"
LOCAL_MODEL_DIR = "/workspace/finetuned-model"


def load_model_and_tokenizer():
    """Load base model with Mxfp4 quantization"""
    logger.info(f"Loading model: {MODEL_NAME}")

    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

    # Mxfp4 quantization for H100 GPU
    quantization_config = Mxfp4Config(dequantize=True)
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_NAME,
        attn_implementation="eager",
        torch_dtype=torch.bfloat16,
        quantization_config=quantization_config,
        use_cache=False,
        device_map="auto",
    )

    logger.info("Model loaded successfully")
    return model, tokenizer


def prepare_peft_model(model):
    """Configure LoRA for efficient fine-tuning"""
    logger.info("Configuring LoRA")

    peft_config = LoraConfig(
        r=8,
        lora_alpha=16,
        target_modules="all-linear",
        target_parameters=[
            "7.mlp.experts.gate_up_proj",
            "7.mlp.experts.down_proj",
            "15.mlp.experts.gate_up_proj",
            "15.mlp.experts.down_proj",
            "23.mlp.experts.gate_up_proj",
            "23.mlp.experts.down_proj",
        ],
    )

    peft_model = get_peft_model(model, peft_config)
    peft_model.print_trainable_parameters()
    return peft_model


def main():
    """Main training pipeline"""
    logger.info("Starting gpt-oss-20b Fine-tuning on AKS")

    # Check GPU
    if not torch.cuda.is_available():
        raise RuntimeError("No GPU available! This script requires CUDA.")

    gpu_name = torch.cuda.get_device_name(0)
    total_memory = torch.cuda.get_device_properties(0).total_memory / (1024**3)
    logger.info(f"GPU: {gpu_name}, Memory: {total_memory:.2f} GB")

    # Initialize Azure Storage
    logger.info("Authenticating to Azure Storage")
    blob_service_client = BlobServiceClient(
        f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net",
        credential=DefaultAzureCredential(),
    )

    # Load dataset
    logger.info(f"Loading dataset: {DATASET_NAME}")
    dataset = load_dataset(DATASET_NAME, split="train")
    logger.info(f"Loaded {len(dataset)} examples")

    # Load model and tokenizer
    model, tokenizer = load_model_and_tokenizer()

    # Prepare PEFT model
    peft_model = prepare_peft_model(model)

    # Training configuration
    training_args = SFTConfig(
        learning_rate=2e-4,
        gradient_checkpointing=True,
        num_train_epochs=1,
        logging_steps=1,
        per_device_train_batch_size=2,
        gradient_accumulation_steps=8,
        max_length=2048,
        warmup_ratio=0.03,
        lr_scheduler_type="cosine_with_min_lr",
        lr_scheduler_kwargs={"min_lr_rate": 0.1},
        output_dir=OUTPUT_DIR,
        save_strategy="epoch",
        logging_dir=f"{OUTPUT_DIR}/logs",
        report_to="none",
    )

    # Initialize and train
    logger.info("Starting training")
    trainer = SFTTrainer(
        model=peft_model,
        args=training_args,
        train_dataset=dataset,
        processing_class=tokenizer,
    )
    train_result = trainer.train()

    logger.info(f"Training complete! Loss: {train_result.training_loss:.4f}")

    # Save model locally
    logger.info(f"Saving model to {LOCAL_MODEL_DIR}")
    trainer.save_model(LOCAL_MODEL_DIR)
    tokenizer.save_pretrained(LOCAL_MODEL_DIR)

    # Upload to Azure Blob Storage
    logger.info("Uploading to Azure Blob Storage")
    container_client = blob_service_client.get_container_client(MODEL_CONTAINER)
    model_blob_prefix = "gpt-oss-20b-multilingual"

    for root, dirs, files in os.walk(LOCAL_MODEL_DIR):
        for file in files:
            local_path = os.path.join(root, file)
            relative_path = os.path.relpath(local_path, LOCAL_MODEL_DIR)
            blob_path = f"{model_blob_prefix}/{relative_path}".replace("\\", "/")

            max_retries = 3
            for attempt in range(1, max_retries + 1):
                try:
                    blob_client = container_client.get_blob_client(blob_path)
                    with open(local_path, "rb") as data:
                        blob_client.upload_blob(data, overwrite=True)
                    logger.info(f"Uploaded: {blob_path}")
                    break
                except Exception as e:
                    if attempt < max_retries:
                        logger.warning(
                            f"Upload failed for {blob_path} (attempt {attempt}/{max_retries}): {e}. Retrying..."
                        )
                    else:
                        logger.error(
                            f"Upload failed for {blob_path} after {max_retries} attempts: {e}"
                        )
                        raise

    logger.info(
        f"Complete! Model saved to: {STORAGE_ACCOUNT_NAME}/{MODEL_CONTAINER}/{model_blob_prefix}"
    )


if __name__ == "__main__":
    main()
