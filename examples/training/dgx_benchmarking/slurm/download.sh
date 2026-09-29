#!/bin/bash

# Download DGX benchmarking recipes
ngc registry resource download-version "nvidia/dgxc-benchmarking/grok1-314b-dgxc-benchmarking-b:25.01"
ngc registry resource download-version "nvidia/dgxc-benchmarking/llama31-8b-dgxc-benchmarking-b:25.01"
ngc registry resource download-version "nvidia/dgxc-benchmarking/llama31-70b-dgxc-benchmarking-b:25.01"
ngc registry resource download-version "nvidia/dgxc-benchmarking/llama31-405b-dgxc-benchmarking-b:25.01"
ngc registry resource download-version "nvidia/dgxc-benchmarking/nemo_megatron175b-dgxc-benchmarking-b:25.01"
ngc registry resource download-version "nvidia/dgxc-benchmarking/maxtext-llama2-70b-dgxc-benchmarking-b:25.01"
ngc registry resource download-version "nvidia/dgxc-benchmarking/nemotron15b-dgxc-benchmarking-b:25.01"
ngc registry resource download-version "nvidia/dgxc-benchmarking/nemotron340b-dgxc-benchmarking-b:25.01"

# Make training directories
mkdir grok1-314b llama31-8b llama31-70b llama31-405b nemo_megatron175b maxtext-llama2 nemotron15b nemotron340b
