



Script to get torset switch:

```
#!/bin/bash
set -euo pipefail

# Collect all HCAs' GUIDs
guids=$(ibv_devinfo | grep hca | awk '{print $2}' \
    | xargs -I% ibstat "%" \
    | grep "Port GUID" | awk -F: '{print $2}' | sed 's/^0x00/0x/')

guid_file=$(mktemp)
echo "$guids" > "$guid_file"

topo_file=$(mktemp)
SHARP_SMX_UCX_INTERFACE=mlx5_0:1 \
    /opt/mellanox/sharp/bin/sharp_cmd topology \
    --ib-dev mlx5_0:1 \
    --guids_file "$guid_file" \
    --topology_file "$topo_file"

# Step 1: Get leaf switches (switches that connect to nodes)
leafs=$(grep "Nodes=" "$topo_file" | awk '{print $1}' | cut -d= -f2)

# Step 2: Get their direct parents
declare -A parent_counts
while read -r line; do
    sw_name=$(echo "$line" | awk '{print $1}' | cut -d= -f2)
    switches_field=$(echo "$line" | grep "Switches=" | awk '{print $2}' | cut -d= -f2)
    IFS=',' read -ra switches <<< "$switches_field"
    for leaf in $leafs; do
        for s in "${switches[@]}"; do
            if [[ "$s" == "$leaf" ]]; then
                parent_counts["$sw_name"]=1
            fi
        done
    done
done < <(grep "Switches=" "$topo_file")

# Step 3: Now get all parents of these parents (one level up)
declare -A torset_candidates
for parent in "${!parent_counts[@]}"; do
    while read -r line; do
        sw_name=$(echo "$line" | awk '{print $1}' | cut -d= -f2)
        switches_field=$(echo "$line" | grep "Switches=" | awk '{print $2}' | cut -d= -f2 || echo "")
        IFS=',' read -ra switches <<< "$switches_field"
        for p in "${switches[@]}"; do
            if [[ "$p" == "$parent" ]]; then
                torset_candidates["$sw_name"]=1
            fi
        done
    done < <(grep "Switches=" "$topo_file")
done

# There should be only one torset
torset=$(printf "%s\n" "${!torset_candidates[@]}" | head -n1)

echo "Torset switch label: $torset"
```



Test container:

```
apiVersion: v1
kind: Pod
metadata:
  name: pytorch-gpu-rdma-pod
  labels:
    app: pytorch
spec:
  containers:
    - name: pytorch-container
      image: mcr.microsoft.com/aznhc/aznhc-nv:1.2.0
      command: ["/bin/bash", "-c", "tail -f /dev/null"] # Keeps the container running for debugging.
      resources:
        limits:
          nvidia.com/gpu: 8
          rdma/ib: 8
        requests:
          nvidia.com/gpu: 8
          rdma/ib: 8
      securityContext:
        capabilities:
          add:
            - SYS_RESOURCE
      volumeMounts:
        - name: host-data
          mountPath: /var/lib/hyperv/.kvp_pool_3
  volumes:
      - name: host-data
        hostPath:
          path: /var/lib/hyperv/.kvp_pool_3
  # The pod's restart policy will be set to Never, ensuring that the pod remains in its current state,
  # preventing it from restarting automatically on failure.
  restartPolicy: Never
```
 

## Install with Helm

This chart deploys a DaemonSet that labels each node with:
- KVP-derived labels from `/var/lib/hyperv/.kvp_pool_3`
- The IB PKey found on the node (`ib/pkey`)
- The fabric torset derived via SHARP tooling (`ib/torset`) when RDMA is available

Prerequisites:
- Cluster-admin permissions to install cluster-scoped RBAC.
- Optional: RDMA device plugin on IB-enabled nodes (torset discovery will gracefully skip if absent).

Install or upgrade the chart from this repository (namespace is `kube-system`):

```bash
helm upgrade --install node-labeler ./utilities/aks/node_labeler/helm -n kube-system
```

Verify rollout:

```bash
kubectl get pods -n kube-system -l app=node-labeler
```

Check labels applied to a node (example):

```bash
kubectl get node <node-name> --show-labels | tr ',' '\n' | egrep '(^|,)hyperv/|ib/pkey|ib/torset'
```

Uninstall:

```bash
helm uninstall node-labeler -n kube-system
```