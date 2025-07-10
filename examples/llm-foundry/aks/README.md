# blob driver

```
az aks update --enable-blob-driver --name myAKSCluster --resource-group myResourceGroup
```

# shared storage setup

First, deploy the shared storage that will be used by both dataset preparation and training:

```
helm install shared-storage helm/shared-storage \
  --set storage.pvcName="shared-blob-storage"
```

This creates a dynamically provisioned blobfuse storage with ReadWriteMany access that can be shared across multiple pods.

# pytorchjob

```
kubectl apply --server-side -k "github.com/kubeflow/training-operator.git/manifests/overlays/standalone?ref=v1.8.1"
```

# dataset prep

```
helm install dataset-prep helm/dataset-download \
  --set storage.pvcName="shared-blob-storage" \
  --set dataset.splits="{train_small,val_small}"
```

# run training

```
helm install llm-training helm/llm-training -n training \
  --set image.tag=latest \
  --set model.config="mpt-125m" \
  --set resources.rdmaResource="rdma/ib" \
  --set storage.pvcName="shared-blob-storage" \
  --set "yamlUpdates.train_loader\.dataset\.split=train_small" \
  --set "yamlUpdates.eval_loader\.dataset\.split=val_small" \
  --set "yamlUpdates.variables\.data_local=/data/my-copy-c4"
```

# todo

* Azure Container Storage (local cache of data rather than blob stream)
* AMLFS
* Monitoring

