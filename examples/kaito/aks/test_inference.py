#!/usr/bin/env python3
"""
KAITO Inference Client Example

This script demonstrates how to interact with a KAITO inference endpoint
using the OpenAI-compatible API.

Usage:
    python test_inference.py --endpoint http://localhost:8080
"""

import argparse
import json
import sys
import requests


def test_completion(endpoint_url, model_name, prompt, max_tokens=256):
    """
    Test the /v1/completions endpoint
    
    Args:
        endpoint_url: Base URL of the inference endpoint
        model_name: Model identifier
        prompt: Input prompt for generation
        max_tokens: Maximum tokens to generate
    
    Returns:
        Generated text
    """
    url = f"{endpoint_url}/v1/completions"
    
    payload = {
        "model": model_name,
        "prompt": prompt,
        "max_tokens": max_tokens,
        "temperature": 0.7,
        "top_p": 0.95
    }
    
    try:
        response = requests.post(
            url,
            json=payload,
            timeout=60
        )
        response.raise_for_status()

        result = response.json()
        return result['choices'][0]['text']

    except requests.exceptions.RequestException as e:
        print(f"Error calling completion endpoint: {e}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"Response: {e.response.text}")
        return None


def test_chat(endpoint_url, model_name, messages, max_tokens=512):
    """
    Test the /v1/chat/completions endpoint
    
    Args:
        endpoint_url: Base URL of the inference endpoint
        model_name: Model identifier
        messages: List of chat messages
        max_tokens: Maximum tokens to generate
    
    Returns:
        Generated response
    """
    url = f"{endpoint_url}/v1/chat/completions"
    
    payload = {
        "model": model_name,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": 0.7,
        "top_p": 0.95
    }
    
    try:
        response = requests.post(
            url,
            json=payload,
            timeout=60
        )
        response.raise_for_status()

        result = response.json()
        return result['choices'][0]['message']['content']

    except requests.exceptions.RequestException as e:
        print(f"Error calling chat endpoint: {e}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"Response: {e.response.text}")
        return None


def main():
    parser = argparse.ArgumentParser(
        description="Test KAITO inference endpoint"
    )
    parser.add_argument(
        "--endpoint",
        default="http://localhost:8080",
        help="Inference endpoint URL (default: http://localhost:8080)"
    )
    parser.add_argument(
        "--model",
        default="microsoft/phi-2",
        help="Model name (default: microsoft/phi-2)"
    )
    parser.add_argument(
        "--mode",
        choices=["completion", "chat"],
        default="completion",
        help="Test mode: completion or chat (default: completion)"
    )
    
    args = parser.parse_args()
    
    print(f"Testing KAITO inference endpoint: {args.endpoint}")
    print(f"Model: {args.model}")
    print(f"Mode: {args.mode}\n")
    
    if args.mode == "completion":
        # Test completion endpoint
        prompt = "What is Azure Kubernetes Service? Explain in simple terms."
        print(f"Prompt: {prompt}\n")
        
        result = test_completion(args.endpoint, args.model, prompt)
        
        if result:
            print("Response:")
            print("-" * 80)
            print(result)
            print("-" * 80)
            return 0
        else:
            print("Failed to get response from completion endpoint")
            return 1
    
    else:
        # Test chat endpoint
        messages = [
            {
                "role": "system",
                "content": "You are a helpful AI assistant specialized in cloud computing and Kubernetes."
            },
            {
                "role": "user",
                "content": "Explain what KAITO (Kubernetes AI Toolchain Operator) does and why it's useful."
            }
        ]
        
        print("Chat Messages:")
        for msg in messages:
            print(f"  {msg['role']}: {msg['content']}")
        print()
        
        result = test_chat(args.endpoint, args.model, messages)
        
        if result:
            print("Response:")
            print("-" * 80)
            print(result)
            print("-" * 80)
            return 0
        else:
            print("Failed to get response from chat endpoint")
            return 1


if __name__ == "__main__":
    sys.exit(main())
