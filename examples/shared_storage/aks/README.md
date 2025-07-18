# Shared Storage Helm Charts for AKS

This directory contains Helm charts for different ReadWriteMany storage options for Azure Kubernetes Service (AKS).

## Available Storage Options

* Blob Shared Storage (`blob-shared-storage`)
* AMLFS Shared Storage (`amlfs-shared-storage`)


# Setting the AMLFS roles

```
#!/bin/bash

set -euo pipefail

# Required variables
AKS_CLUSTER=$1
AZURE_RESOURCE_GROUP=$2
ROLE_NAME="amlfs-dynamic-csi-roles"
CUSTOM_ROLE_FILE="custom-role.json"

# Get the subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Get the kubelet identity objectId
echo "Fetching kubelet identity..."
KUBELET_IDENTITY=$(az aks show \
  --name "$AKS_CLUSTER" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query identityProfile.kubeletidentity \
  -o json)

OBJECT_ID=$(echo "$KUBELET_IDENTITY" | jq -r '.objectId')

# Define the custom role if not exists
echo "Checking for existing custom role..."
ROLE_ID=$(az role definition list --name "$ROLE_NAME" --query "[].name" -o tsv)

if [ -z "$ROLE_ID" ]; then
  echo "Creating custom role: $ROLE_NAME"

  cat > $CUSTOM_ROLE_FILE <<EOF
{
  "Name": "$ROLE_NAME",
  "IsCustom": true,
  "Description": "Custom role for Kubelet access to AML FS and subnet operations",
  "Actions": [
    "Microsoft.Network/virtualNetworks/subnets/read",
    "Microsoft.Network/virtualNetworks/subnets/join/action",
    "Microsoft.StorageCache/getRequiredAmlFSSubnetsSize/action",
    "Microsoft.StorageCache/checkAmlFSSubnets/action",
    "Microsoft.StorageCache/amlFilesystems/read",
    "Microsoft.StorageCache/amlFilesystems/write",
    "Microsoft.StorageCache/amlFilesystems/delete"
  ],
  "NotActions": [],
  "AssignableScopes": ["/subscriptions/$SUBSCRIPTION_ID"]
}
EOF

  az role definition create --role-definition $CUSTOM_ROLE_FILE
else
  echo "Custom role already exists: $ROLE_NAME"
fi

# Assign the custom role to the kubelet identity
echo "Assigning role to kubelet identity..."
az role assignment create \
  --assignee-object-id "$OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "$ROLE_NAME" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

echo "Role assignment completed."
```
