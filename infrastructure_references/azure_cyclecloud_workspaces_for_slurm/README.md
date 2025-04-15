# Deploying Azure CycleCloud Workspaces for Slurm

This section of the repository contains the guidance to deploy Azure CycleCloud Workspaces for Slurm environments.

The templates contained in this folder have some deployment examples with different features and storage types.

The deployment guide follows what described in the [official Azure CycleCloud Workspaces for Slurm documentation pages](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/ccws/deploy-with-cli?view=cyclecloud-8).

## Prequisites

In order to deploy the infrastructure described in this section of the guide in an existing Azure Subscription, be sure to have:
* A working installation of [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt)
* Contributor on the Subscription
* User Access Administrator on the Subscription
* Be sure that `az account show` is displaying the right subscription. In case, fix the subscription with `az account set --subscription "your-subscription-name"`


## Define the environment variables

In order to customize the templates according to your specific configuration needs, you can manually edit a copy of the templates.
There are however a series of parameters that can be passed defining some environment variables and using `envsubst`.

### Large AI Training Cluster

In order to define the deployment logic of the `large-ai-training-cluster-parameters.json` the following environment variables are required.

```bash
export LOCATION="your-azure-region"               # Azure region for resource deployment (e.g., eastus, westus2)
export USERNAME="your-admin-username"            # Administrator username for Azure CycleCloud UI
export PASSWORD="your-admin-password"            # Administrator password for Azure CycleCloud UI
export SSH_PUBLIC_KEY="your-ssh-public-key"      # Public SSH key for secure access to all cluster nodes and Azure CycleCloud VM
export RESOURCE_GROUP_NAME="your-resource-group" # Azure resource group name for deployment
export NETWORK_RANGE="10.0.0.0/16"               # Address space for the virtual network in CIDR notation (if template creates a new VNET)
export DB_PASSWORD="your-db-password"            # MySQL Database administrator password (if required by the template)
export DB_USERNAME="your-db-username"            # MySQL Database administrator username (if required by the template)
export DB_NAME="your-database-name"              # Name of the MySQL database (if required by the template)
export MYSQL_ID="your-mysql-id"                  # Unique identifier for the MySQL database resource (if required by the template)
```

The deployment ready file can be generated with the following commands:

```bash
envsubst < large-ai-training-cluster-parameters.json large-ai-training-cluster-parameters_deploy.json
```
> [!WARNING]  
> Check other parameters in the template before proceeding with the deployment, like AMLFS file system size, the desired SKU and size.

## (Optional) Create a MySQL Flexible server
Some of the templates in this folder require the presence of a pre-existing MySQL Flexible server for Slurm job accounting.

This is a prerequisites for some of the deployments below.

In order to deploy the smallest MySQL Flexible server, with the lowest tier:

```bash
az mysql flexible-server create \
  --name $DB_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --location $LOCATION \
  --admin-user $DB_USERNAME$ \
  --admin-password $DB_PASSWORD \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 20 \
  --backup-retention 0 \
  --high-availability Disabled \
   --public-access 'None'
```

## Deploy the Azure CycleCloud Slurm Workspaces environment

> [!WARNING]  
> Check other parameters in the template before proceeding with the deployment, like AMLFS file system size, the desired SKU and size.


```bash
az login --tenant <your-tenant-id>
az account show ### Check you are in the right subscription
az account set --subscription "your-subscription-name" ### In case you are not in the right one
git clone --depth 1 --branch 2025.02.06 https://github.com/azure/cyclecloud-slurm-workspace.git
cd cyclecloud-slurm-workspace
az deployment sub create --template-file bicep/mainTemplate.bicep --parameters <YOUR_TEMPLATE_FILE>_deploy.json --location $LOCATION
```