# Deploying Azure CycleCloud Workspace for Slurm

This section of the repository contains the guidance to deploy Azure CycleCloud Workspace for Slurm environments.

The templates contained in this folder have some deployment examples with different features and storage types.

The deployment guide follows what described in the [official Azure CycleCloud Workspace for Slurm documentation pages](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/ccws/deploy-with-cli?view=cyclecloud-8).

## Prequisites

In order to deploy the infrastructure described in this section of the guide in an existing Azure Subscription, be sure to have:

- A working installation of [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt)
- Contributor on the Subscription
- User Access Administrator on the Subscription
- Be sure that `az account show` is displaying the right subscription. In case, fix the subscription with `az account set --subscription "your-subscription-name"`

## Define the environment variables

In order to customize the templates according to your specific configuration needs, you can manually edit a copy of the templates.
There are however a series of parameters that can be passed defining some environment variables and using `envsubst`.

### Large AI Training Cluster

In order to define the deployment parameters in `large-ai-training-cluster-parameters-deploy.json` the following environment variables are required.

```bash
export LOCATION="your-azure-region"              # Azure region for resource deployment (e.g., eastus, westus2)
export USERNAME="your-admin-username"            # Administrator username for Azure CycleCloud UI
export PASSWORD="your-admin-password"            # Administrator password for Azure CycleCloud UI
export SSH_PUBLIC_KEY="your-ssh-public-key"      # Public SSH key for secure access to all cluster nodes and Azure CycleCloud VM
export RESOURCE_GROUP_NAME="your-resource-group" # Azure resource group name for deployment
export NETWORK_RANGE="10.0.0.0/21"               # Address space for the virtual network in CIDR notation (if template creates a new VNET)
export DB_PASSWORD="your-db-password"            # MySQL Database administrator password (if required by the template)
export DB_USERNAME="your-db-username"            # MySQL Database administrator username (if required by the template)
export DB_NAME="your-database-name"              # Name of the MySQL database (if required by the template)
export ANF_SKU="Premium"                         # SKU for Azure NetApp Files
export ANF_SIZE=4                                # Size for Azure NetApp Files (Standard | Premium | Ultra)
export AMLFS_SKU="AMLFS-Durable-Premium-500"     # SKU for AMLFS (AMLFS-Durable-Premium-40 | AMLFS-Durable-Premium-125 | AMLFS-Durable-Premium-250 | AMLFS-Durable-Premium-500)
export AMLFS_SIZE=128                            # Size for Azure Managed Lustre
export GPU_SKU="Standard_ND96isr_H100_v5"        # GPU Node SKU
export GPU_NODE_COUNT=64                         # Number of GPU nodes at maximum scale
```

> [!WARNING]  
> Check other parameters in the template before proceeding with the deployment, like AMLFS file system size and the desired SKU.

## Create a MySQL Flexible server

Some of the templates in this folder require the presence of a pre-existing MySQL Flexible server for Slurm job accounting.

This is a prerequisites for some of the deployments below.

In order to deploy the smallest MySQL Flexible server, with the lowest tier:

```bash
az mysql flexible-server create \
  --name $DB_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --location $LOCATION \
  --admin-user $DB_USERNAME \
  --admin-password $DB_PASSWORD \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 20 \
  --high-availability Disabled \
   --public-access 'None'
```

Let's then export the ID in a variable for the subsequent steps:

```bash
export MYSQL_ID=$( az mysql flexible-server show -n $DB_NAME -g $RESOURCE_GROUP_NAME --query "id" --output tsv)
```

## Create the parameters file

The deployment ready file can be generated with the following commands after the steps described in the previous paragraphs are completed:

```bash
envsubst < large-ai-training-cluster-parameters.template > large-ai-training-cluster-parameters-deploy.json
```

## Deploy the Azure CycleCloud Slurm Workspace environment

> [!WARNING]  
> Check other parameters in the template before proceeding with the deployment, like AMLFS file system size and the desired SKU.

```bash
export TENANT_ID="your-tenant-id"
export SUBSCRIPTION_NAME="your-subscription-name"
az login --tenant $TENANT_ID
az account show ### Check you are in the right subscription
az account set --subscription $SUBSCRIPTION_NAME ### In case you are not in the right one
git clone --depth 1 --branch 2025.02.06 https://github.com/azure/cyclecloud-slurm-workspace.git
az deployment sub create --template-file cyclecloud-slurm-workspace/bicep/mainTemplate.bicep --parameters large-ai-training-cluster-parameters-deploy.json --location $LOCATION
```
