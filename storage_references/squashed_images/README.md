# Squashed image file tuning

## Introduction

For a Slurm cluster using `pyxis` and `enroot` for multi-node and multi-GPU container runs, during the training job startup, all the cluster nodes will read the squashed image files from the shared file-system, generating a start-up storm on a single file read.

In this example we will be taking a PyTorch image, this means that approximately 23 GiB of data will be read in a single file by hundreds of nodes, requiring an overall egress in the order of several TiBs from the filesystem.

Potential solutions to manage this initial I/O are:

- [Adjusting the striping](#adjusting-azure-managed-lustre-striping) configuration if the `sqsh` file is stored on an Azure Managed Lustre instance
- [Staging](#staging-in-local-nvme) the `sqsh` file in the local NVME of the GPU nodes

## Adjusting Azure Managed Lustre striping

If the image file just keeps default Azure Managed Lustre striping configuration, this may lead to get most of the I/O pressure on a limited number of OSSs.

If we run the `lfs getstripe` command on the downloaded images without any custom striping, we will see that only 6 OSSs are hosting the file. This is related to the default PFL configuration of AMLFS striping.

In the following commands we assume the presence of some environment variables for the stage path, the AMLFS mount point and image name of the sqsh file:

```bash
export STAGE_PATH="your-stage-path"
export MOUNT_PATH="lustre-mount-point"
export IMAGE_NAME="your-image-name"
```

```bash
lfs getstripe ${STAGE_PATH}/${IMAGE_NAME}.sqsh
...
     lmm_objects:
      - 0: { l_ost_idx: 5, l_fid: [0x100050000:0x38418:0x0] }
...
      lmm_objects:
      - 0: { l_ost_idx: 3, l_fid: [0x100030000:0x38369:0x0] }
      - 1: { l_ost_idx: 9, l_fid: [0x100090000:0x383c6:0x0] }
      - 2: { l_ost_idx: 8, l_fid: [0x100080000:0x3833f:0x0] }
      - 3: { l_ost_idx: 4, l_fid: [0x100040000:0x38338:0x0] }
      - 4: { l_ost_idx: 2, l_fid: [0x100020000:0x3841c:0x0] }
```

The striping of the file can be optimized to ensure that reads happen with cooperation of all the OSSs (this requires superuser privileges). Below we create a new folder striped on all OSSs (`-c -1`) and we copy the image inside the new folder:

```bash
mkdir ${STAGE_PATH}/striped_directory
lfs setstripe -S 1M -E -1 -c -1  ${STAGE_PATH}/striped_directory
cp ${STAGE_PATH}/${IMAGE_NAME}.sqsh ${STAGE_PATH}/striped_directory
```

The container image to be used in `srun` command then becomes `${STAGE_PATH}/striped_directory/${IMAGE_NAME}.sqsh`:

```bash
srun --container-image=${STAGE_PATH}/striped_directory/${IMAGE_NAME}.sqsh ...
```

Here is a comparison on an `AMLFS 500 - 128 TiB` of the time to startup with `srun` a squashed image of PyTorch (23 GiB) from the Azure Managed Lustre Filesystem with different striping settings:

| Setting              | OST occupation | Container startup time on 64 nodes [s] |
| -------------------- | -------------- | -------------------------------------- |
| Default striping     | 1 x 23 GiB     | 200                                    |
| Full 32 OST striping | 1 x 23 GiB     | 74                                     |

## Staging in local NVME

Alternatively to adjusting Azure Managed Lustre striping, it is possible to stage the image in the local NVME disks of the GPU nodes (which are automatically paired in a software RAID 0 under `/mnt/nvme` in an Azure CycleCloud Workspace for Slurm deployment).

This can be achieved using in the Slurm execution script:

```bash
export STAGE_PATH="your-stage-path"
export MOUNT_PATH="lustre-mount-point"
export IMAGE_NAME="your-image-name"
export NVME_IMAGE_PATH="/mnt/nvme/${IMAGE_NAME}"

rsync -avSH ${STAGE_PATH}/${IMAGE_NAME} ${NVME_IMAGE_PATH}
```

Then in the `srun` command, the image to be used as container image is:

```bash
srun --container-image=${NVME_IMAGE_PATH} ...
```

Using `rsync` the image will be copied only if not present in the local NVME path of the nodes on job startup. This however should not be the case most of the times if nodes are kept allocated in the environment with data persisting on the NVME drives.
