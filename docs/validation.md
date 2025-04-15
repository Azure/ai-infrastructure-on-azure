# Validation & Health Checks

This section covers how to verify that your Azure supercomputing cluster is functioning correctly after deployment. It includes hardware validation, integration checks, and best practices for ongoing health monitoring.

## 1. Cluster Bring-up Validation

After provisioning, validate that all nodes:

- Are reachable via SSH
- Have the correct VM SKU and expected hardware configuration
- Are configured with the expected InfiniBand topology
- Appear in your scheduler or orchestration system (e.g., Slurm, Kubernetes)

Use `lshw`, `nvidia-smi`, and `ibstat` to confirm basic hardware presence and status.

## 2. Node Health Checks

Azure provides a Node Health Check (NHC) toolkit via the AzHPC project, which verifies:

- GPU enumeration and driver status
- ECC error state
- InfiniBand connectivity and performance
- PCIe/NVMe health
- Clock and thermal sanity
- NCCL functional tests

To run NHC:

```bash
git clone https://github.com/Azure/azhpc-validation
cd azhpc-validation
bash scripts/run-validation.sh
```

You can run this post-deployment and periodically as a diagnostic.

## 3. Scheduler Integration

If using Slurm:

- Confirm that nodes are visible with `sinfo`
- Nodes should be marked `idle` or `alloc` once healthy
- Slurm NHC plugins can run pre-job checks and evict failing nodes

If using Kubernetes:

- Confirm GPU node readiness with `kubectl get nodes -o wide`
- Ensure `nvidia-device-plugin` is running
- Optionally, use a DaemonSet to run health checks regularly

## 4. Common Failures

These issues should be remediated or reported via GHR:

- GPUs not visible in `nvidia-smi`
- InfiniBand link down or degraded (`ibstat`, `ibstatus`)
- Persistent ECC or double-bit errors
- PCIe bus errors or NUMA misalignment
- Nodes that hang or reboot under load

## 5. Best Practices

- Run NHC after every deployment and weekly thereafter
- Log all validation output centrally
- Automate node drain + notify on health failure
- Track flaky vs consistently bad nodes separately

---

Next: [Operations](operations.md)
