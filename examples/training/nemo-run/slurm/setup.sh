#!/bin/bash

# Function to install uv
install_uv() {
	printf "Installing 'uv'...\n"
	curl -LsSf https://astral.sh/uv/install.sh | sh

	printf "Adding 'uv' to PATH...\n"
	source $HOME/.local/bin/env
}

# Check if 'uv' is installed
if command -v uv >/dev/null 2>&1; then
	printf "'uv' is already installed.\n"
else
	install_uv
fi

# Create a new uv environment for the project
printf "Creating a new uv environment named 'ccws-nemo-venv' with Python 3.10.12...\n"
uv venv --python 3.10.12 $HOME/ccws-nemo-venv

# Activate the new environment
printf "Activating the 'ccws-nemo-venv' environment...\n"
source $HOME/ccws-nemo-venv/bin/activate

# Install required packages
printf "Installing required packages...\n"
uv pip install torch==2.6.0 torchvision torchaudio
uv pip install pytorch-lightning===2.5.0
uv pip install megatron-core===0.11.0
uv pip install nemo_toolkit['all']==2.2.0

printf "Installing nemo-run...\n"
uv pip install nemo-run===0.3.0

printf "Installing jupyterlab...\n"
uv pip install jupyterlab
