# blob driver

az aks update --enable-blob-driver --name myAKSCluster --resource-group myResourceGroup

# setup storage

```
#!/bin/bash

# Configuration
CLUSTER_NAME=
AZURE_RESOURCE_GROUP=
LOCATION=
STORAGE_ACCOUNT_NAME="${CLUSTER_NAME}blob$(date +%s)"  # Unique name
CONTAINER_NAME="data"

echo "Setting up blob storage with CSI drivers for AKS cluster: $CLUSTER_NAME"

# Create storage account
echo "Creating storage account: $STORAGE_ACCOUNT_NAME"
az storage account create \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $LOCATION \
    --sku Standard_LRS \
    --kind StorageV2

# Create blob container
echo "Creating blob container: $CONTAINER_NAME"
az storage container create \
    --name $CONTAINER_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    --auth-mode login

# Enable blob CSI driver on AKS cluster with latest version
echo "Enabling blob CSI driver on AKS cluster..."
az aks update \
    --resource-group $AZURE_RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --enable-blob-driver

# Get AKS managed identity
echo "Getting AKS managed identity..."
KUBELET_IDENTITY_ID=$(az aks show \
    --resource-group $AZURE_RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --query "identityProfile.kubeletidentity.clientId" -o tsv)

KUBELET_IDENTITY_RESOURCE_ID=$(az aks show \
    --resource-group $AZURE_RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --query "identityProfile.kubeletidentity.resourceId" -o tsv)

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Assign Storage Blob Data Contributor role to kubelet identity
echo "Assigning Storage Blob Data Contributor role..."
az role assignment create \
    --assignee $KUBELET_IDENTITY_ID \
    --role "Storage Blob Data Contributor" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"

echo "export STORAGE_ACCOUNT=$STORAGE_ACCOUNT_NAME" > env.sh
echo "export AZURE_RESOURCE_GROUP=$AZURE_RESOURCE_GROUP" >> env.sh
echo "export SUBSCRIPTION_ID=$SUBSCRIPTION_ID" >> env.sh
echo "export KUBELET_IDENTITY_RESOURCE_ID=$KUBELET_IDENTITY_RESOURCE_ID" >> env.sh
echo "Created env.sh with environment variables.  Source it with 'source env.sh' to use in your session."


echo "Setup complete!"
```

# pytorchjob

kubectl apply --server-side -k "github.com/kubeflow/training-operator.git/manifests/overlays/standalone?ref=v1.8.1"

# dataset prep

helm install dataset-prep . --set storage.azureBlob.storageAccountName="$STORAGE_ACCOUNT" --set storage.azureBlob.kubeletIdentityResourceID="$KUBELET_IDENTITY_RESOURCE_ID" --set dataset.splits="{train_small,val_small}"

# run training

```
helm install llm-training . -n training \
  --set image.tag=latest \
  --set model.config="mpt-125m" \
  --set resources.rdmaResource="rdma/ib" \
  --set storage.azureBlob.storageAccountName="$STORAGE_ACCOUNT" \
  --set storage.azureBlob.kubeletIdentityResourceID="$KUBELET_IDENTITY_RESOURCE_ID" \
  --set "yamlUpdates.train_loader\.dataset\.split=train_small" \
  --set "yamlUpdates.eval_loader\.dataset\.split=val_small" \
  --set "yamlUpdates.variables\.data_local=/data/my-copy-c4"
```

# todo

* Azure Container Storage (local cache of data rather than blob stream)
* AMLFS
* Monitoring
