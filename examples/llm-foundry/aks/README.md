# blob driver

```
az aks update --enable-blob-driver --name myAKSCluster --resource-group myResourceGroup
```

# install cert manager

> Needed by pytorchjob

```
helm repo add jetstack https://charts.jetstack.io --force-update

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.18.2 \
  --set crds.enabled=true
```

# pytorchjob

```
kubectl apply --server-side -k "github.com/kubeflow/training-operator.git/manifests/overlays/standalone?ref=v1.8.1"
```

# shared storage setup

First, deploy the shared storage that will be used by both dataset preparation and training:

```
helm install shared-storage helm/shared-storage \
  --set storage.pvcName="shared-blob-storage"
```

This creates a dynamically provisioned blobfuse storage with ReadWriteMany access that can be shared across multiple pods.

# dataset prep

```
helm install dataset-prep helm/dataset-download \
  --set storage.pvcName="shared-blob-storage" \
  --set dataset.outputPath="my-copy-c4" \
  --set dataset.splits="{train_small,val_small}"
```

# run training

This will stage the data to the local `/tmp` asynchronously.  This will be a local disk provided ephemeral OS disk is used for the node pool.  Alternatives would be using an NVME with the local disk provisioner.  However the best approach with be to use Azure Container Storage aggregating all the NVME disks.  However, this feature is due for GA next month and will updated when released.

```
helm install llm-training helm/llm-training \
  --set image.tag=latest \
  --set model.config="mpt-125m" \
  --set resources.rdmaResource="rdma/ib" \
  --set storage.pvcName="shared-blob-storage" \
  --set "yamlUpdates.train_loader\.dataset\.split=train_small" \
  --set "yamlUpdates.eval_loader\.dataset\.split=val_small" \
  --set "yamlUpdates.variables\.data_remote=/data/my-copy-c4" \
  --set "yamlUpdates.variables\.data_local=/tmp/my-copy-c4"
```

This is an example with checkpoints:

```
helm install llm-training helm/llm-training \
  --set image.tag=latest \
  --set model.config="mpt-125m" \
  --set resources.rdmaResource="rdma/ib" \
  --set storage.pvcName="shared-blob-storage" \
  --set "yamlUpdates.train_loader\.dataset\.split=train_small" \
  --set "yamlUpdates.eval_loader\.dataset\.split=val_small" \
  --set "yamlUpdates.variables\.data_remote=/data/my-copy-c4" \
  --set "yamlUpdates.variables\.data_local=/tmp/my-copy-c4" \
  --set "yamlUpdates.variables\.save_folder=/tmp/checkpoints" \
  --set "yamlUpdates.variables\.save_interval=500ba" \
  --set "yamlUpdates.variables\.save_num_checkpoints_to_keep=10" \
  --set "yamlUpdates.variables\.fdsp_config\.state_dict_type=sharded"
```


# todo

* update installer for blob storage
* update installer for pytorchjob
* Checkpoints
 - can be in /data/checkpoints
* Azure Container Storage (use aggregate bandwidth of all the NVME disks in the node) - waiting for GA
* AMLFS
* Monitoring

