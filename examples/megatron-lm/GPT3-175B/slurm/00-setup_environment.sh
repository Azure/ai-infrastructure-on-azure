#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --mem=0
set -xe

if [ -z "$STAGE_PATH" ]; then
  echo "Please set the STAGE_PATH environment variable to the path where you want to store the image."
  exit 1
fi

## VERSIONS
PYTORCH_VERSION=${PYTORCH_VERSION:-"25.03"}
LAUNCHER_VERSION=${NEMO_VLAUNCHER_VERSIONERSION:-"24.12"}
NEMO_VERSION=${NEMO_VERSION:-"24.05"}
MEGATRON_LM_VERSION=${MEGATRON_LM_VERSION:-"e958b2ca"}

## PYTORCH
PYTORCH_DOCKER_IMAGE="nvcr.io#nvidia/pytorch:${PYTORCH_VERSION}-py3"
SQUASHED_PYTORCH_IMAGE_NAME="pytorch+${PYTORCH_VERSION}+py3"
SQUASHED_PYTORCH_IMAGE="$STAGE_PATH/${SQUASHED_PYTORCH_IMAGE_NAME}.sqsh"
srun enroot import --output $SQUASHED_PYTORCH_IMAGE docker://$PYTORCH_DOCKER_IMAGE 

## NEMO
NEMO_DOCKER_IMAGE="nvcr.io#nvidia/nemo:${NEMO_VERSION}"
SQUASHED_NEMO_IMAGE_NAME="nemo+${NEMO_VERSION}"
SQUASHED_NEMO_IMAGE="$STAGE_PATH/${SQUASHED_NEMO_IMAGE_NAME}.sqsh"
srun enroot import --output $SQUASHED_NEMO_IMAGE docker://$NEMO_DOCKER_IMAGE 

## NEMO LAUNCHER
git clone --single-branch --branch $LAUNCHER_VERSION  https://github.com/NVIDIA/NeMo-Framework-Launcher.git $STAGE_PATH/NeMo-Framework-Launcher

## MEGATRON LM 
git clone https://github.com/NVIDIA/Megatron-LM.git $STAGE_PATH/Megatron-LM
cd $STAGE_PATH/Megatron-LM
git checkout $MEGATRON_LM_VERSION