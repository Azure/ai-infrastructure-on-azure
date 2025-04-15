# Deployment Guide

This section describes how to deploy Azure GPU Supercomputing infrastructure, with options for CLI-based provisioning, infrastructure-as-code tools, and key networking considerations.

## 1. Choose a Deployment Method

Azure Supercomputing clusters can be deployed using the following options:

- **Azure CLI** – for lightweight manual provisioning and testing  
- **Bicep or ARM templates** – for reproducible and auditable deployments  
- **Terraform** – popular among infrastructure teams for cloud-agnostic deployment  
- **AzHPC** – Microsoft-supported toolkit for deploying tightly coupled HPC clusters with InfiniBand  

> **Recommendation:** Use AzHPC for complex topologies or when IB tuning is required.

## 2. Define Your Topology

Define:

- Desired VM SKU (NDv4 or NDv5)  
- Number of nodes  
- InfiniBand network topology (e.g., flat, SHARP-enabled, non-SHARP)  
- Placement policies (e.g., proximity placement groups)  

Use the appropriate parameters or variable files depending on your tooling.

## 3. Configure Networking

Ensure the following:

- VNet and subnet are provisioned with sufficient IPs  
- Accelerated networking is enabled  
- NSGs allow SSH, telemetry, and any required workload ports  
- If using IB, ensure the correct partitioning and ToR topology alignment  

## 4. Provision Resources

Example CLI steps:

```bash
az group create -n myResourceGroup -l eastus

az vm create \
  --resource-group myResourceGroup \
  --name myVM \
  --image OpenLogic:CentOS-HPC:7_9:latest \
  --size Standard_ND96asr_v4 \
  --vnet-name myVNet \
  --subnet mySubnet \
  --admin-username azureuser \
  --ssh-key-values ~/.ssh/id_rsa.pub
  ```
Replace with your VM SKU, region, and networking details.

## 5. Post-Deployment Validation

After deployment, verify:

- Node health (see the [Validation](validation.md) section)  
- IB topology and functionality (see the [Topology](topology.md) section)  
- Telemetry pipeline is functional (see the [Telemetry](telemetry.md) section)  

## 6. Automation and Scaling

We recommend integrating deployment pipelines into your CI/CD system for reproducibility. For scale-out, consider:

- VM Scale Sets (VMSS) with custom image  
- Azure CycleCloud  
- AzHPC scripts with looped host creation  

---

Next: [VM SKU Reference](vm-skus.md)
