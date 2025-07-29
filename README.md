# AI Infrastructure on Azure

This repository collects architectural guidance and AI training examples meant to run on Azure AI Infrastructure.

This includes infrastructure examples and real use case scenarios on Azure AI Infrastructure involving different orchestration solutions:

- [Azure CycleCloud Workspace for Slurm](https://learn.microsoft.com/en-us/azure/cyclecloud/overview-ccws?view=cyclecloud-8)
- [Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/aks/what-is-aks)
- [Azure Machine Learning](https://learn.microsoft.com/en-us/azure/machine-learning/?view=azureml-api-2)

For each scenario and architecture, the repository will include storage recommendations among Azure Storage services ([Azure Blob Storage](https://azure.microsoft.com/en-us/products/storage/blobs),
[Azure Managed Lustre](https://learn.microsoft.com/en-us/azure/azure-managed-lustre/amlfs-overview), [Azure NetApp Files](https://learn.microsoft.com/en-us/azure/azure-netapp-files/azure-netapp-files-introduction)), monitoring and observability.

## Infrastructure references catalog

1. [Azure CycleCloud Slurm Workspace AI Cluster](./infrastructure_references/azure_cyclecloud_workspace_for_slurm/README.md) - Prototypes for the creation of Azure CycleCloud Slurm Workspace AI Clusters using CLI deployment
2. [Azure Kubernetes Service Cluster](./infrastructure_references/aks/README.md) - Deployment script for AKS cluster 

## AI training example catalog

1. MegatronLM GPT3-175B with Slimpajama 627B dataset - Example of an end-to-end training workflow based on MegatronLM, including data pre-processing from Slimpajama 627B dataset
   - [Slurm version](./examples/megatron-lm/GPT3-175B/slurm/README.md)
   - [AKS version](./examples/megatron-lm/GPT3-175B/aks/README.md)
2. LLM Foundry MPT Training - Example of an end-to-end training workflow of Mosaic Pretrained Transformer (MPT) model on [C4](https://huggingface.co/datasets/allenai/c4) dataset, based on LLM Foundry
   - [Slurm version](./examples/llm-foundry/slurm/README.md)
   - [AKS version](./examples/llm-foundry/aks/README.md)

## Infrastructure validation catalog

1. NCCL All-reduce - Testing distributed communication performance for multi-GPU training
   - [Slurm version](./infrastructure_validations/slurm/NCCL/README.md)
   - [AKS version](./infrastructure_validations/aks/NCCL/README.md)
2. Node Health Checks - Automated system validation and monitoring for compute nodes
   - [Slurm version](./infrastructure_validations/slurm/NHC/README.md)
   - [AKS version](./infrastructure_validations/aks/NHC/README.md)
3. Thermal Test - GPU thermal stress testing and monitoring
   - [Slurm version](./infrastructure_validations/slurm/thermal_test/README.md)
4. FIO Storage Performance Testing - I/O performance testing with Azure Blob Storage and blobfuse
   - [AKS version](./infrastructure_validations/aks/blobfuse/README.md)

## Contributing

This project welcomes contributions and suggestions. Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit <https://cla.opensource.microsoft.com>.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos is subject to those third-party's policies.

## Contributors

Please join us in contributing to the project

[![Contributors](https://contrib.rocks/image?repo=Azure/ai-on-azure)](https://github.com/Azure/ai-infrastructure-on-azure/graphs/contributors)
