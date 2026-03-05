---
name: azure-node-health-report
description: "File Azure Guest Health Reports for node investigation or replacement. Complete impact category reference (26 categories), PhysicalHostName and Resource ID collection, REST API format, and insight polling."
---

# Azure Node Health Report (GHR)

How to file an Azure Guest Health Report to request node investigation or replacement. Includes the complete impact category reference from official Microsoft documentation, data collection procedures, and REST API format.

**Reference**: [Report node health by using Guest Health Reporting](https://learn.microsoft.com/en-us/azure/azure-impact-reporting/guest-health-impact-report) | [Impact categories](https://learn.microsoft.com/en-us/azure/azure-impact-reporting/guest-health-impact-categories)

## Data Collection — Do This FIRST

**ALWAYS collect node metadata before rebooting or draining.** If the node goes down, you lose access to IMDS and KVP data needed for the GHR.

### 1. Get the PhysicalHostName (REQUIRED)

The PhysicalHostName identifies the physical server hosting the VM. It is read from Hyper-V KVP (Key-Value Pair) pool 3.

```bash
# On the target node
tr -d '\0' < /var/lib/hyperv/.kvp_pool_3 2>/dev/null | sed -e 's/.*Qualified\(.*\)VirtualMachineDynamic.*/\1/'
```

This returns a string like `GGBB90904476`.

**All HPC impact requests must include PhysicalHostName.** Without it, Azure cannot identify the physical server for remediation.

### 2. Get the Resource ID (REQUIRED)

The Resource ID is the fully qualified ARM path to the VM. Query it from the Azure Instance Metadata Service (IMDS):

```bash
# On the target node
curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01"
```

Parse the JSON response to construct the resource ID:

```
/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Compute/virtualMachines/{name}
```

Some images return `resourceId` directly in the response. If not, construct it from `subscriptionId`, `resourceGroupName`, and `name` fields.

### 3. Get the VmUniqueId (recommended)

```bash
# On the target node
cat /sys/class/dmi/id/product_uuid 2>/dev/null || \
  curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-02-01&format=text"
```

### 4. GPU details (optional, speeds up recovery)

For GPU-related GHRs, include as much detail as possible:

```bash
# GPU serial numbers and PCIe locations
nvidia-smi --query-gpu=index,serial,pci.bus_id,name --format=csv,noheader

# For a specific bad GPU (e.g., GPU 2)
nvidia-smi -i 2 --query-gpu=serial,pci.bus_id,name --format=csv,noheader
```

## Impact Categories — Complete Reference

Source: [Impact categories for Guest Health Reporting](https://learn.microsoft.com/en-us/azure/azure-impact-reporting/guest-health-impact-categories)

Three main types:
- **Reset**: Refresh node health state.
- **Reboot**: Request node restart.
- **Unhealthy**: Node has issues — take out of production for diagnostics and repair.

### Full Category List

| Category | Description | Node Removed? |
|----------|-------------|:------------:|
| `Resource.Hpc.Reset` | Reset node health status | No |
| `Resource.Hpc.Reboot` | Restart the node | No |
| `Resource.Hpc.Unhealthy.HpcMissingGpu` | Missing GPU | Yes |
| `Resource.Hpc.Unhealthy.MissingIB` | Missing InfiniBand port | Yes |
| `Resource.Hpc.Unhealthy.IBPerformance` | Degraded InfiniBand performance | Yes |
| `Resource.Hpc.Unhealthy.IBPortDown` | InfiniBand port is in a down state | Yes |
| `Resource.Hpc.Unhealthy.IBPortFlapping` | InfiniBand port flapping | Yes |
| `Resource.Hpc.Unhealthy.HpcGpuDcgmDiagFailure` | DCGMI diagnostic failure | Yes |
| `Resource.Hpc.Unhealthy.HpcRowRemapFailure` | GPU row remapping failure | Yes |
| `Resource.Hpc.Unhealthy.HpcInforomCorruption` | GPU infoROM corruption | Yes |
| `Resource.Hpc.Unhealthy.HpcGenericFailure` | Issue doesn't fit other categories | Yes |
| `Resource.Hpc.Unhealthy.ManualInvestigation` | Request manual investigation by HPC team | Yes |
| `Resource.Hpc.Unhealthy.XID95UncontainedECCError` | GPU uncontained ECC error (XID 95) | Yes |
| `Resource.Hpc.Unhealthy.XID94ContainedECCError` | GPU contained ECC error (XID 94) | Yes |
| `Resource.Hpc.Unhealthy.XID79FallenOffBus` | GPU fell off PCIe bus (XID 79) | Yes |
| `Resource.Hpc.Unhealthy.XID48DoubleBitECC` | GPU double-bit ECC error (XID 48) | Yes |
| `Resource.Hpc.Unhealthy.UnhealthyGPUNvidiasmi` | nvidia-smi unresponsive | Yes |
| `Resource.Hpc.Unhealthy.NvLink` | NVLink is down | Yes |
| `Resource.Hpc.Unhealthy.HpcDcgmiThermalReport` | DCGMI thermal violations | Yes |
| `Resource.Hpc.Unhealthy.ECCPageRetirementTableFull` | Page retirements over threshold | Yes |
| `Resource.Hpc.Unhealthy.DBEOverLimit` | >10 retired pages for double-bit ECC in 7 days | Yes |
| `Resource.Hpc.Unhealthy.GpuXIDError` | GPU XID error (other than 48, 79, 94, 95) | Yes |
| `Resource.Hpc.Unhealthy.AmdGpuResetFailed` | AMD GPU unrecoverable reset failure | Yes |
| `Resource.Hpc.Unhealthy.EROTFailure` | GPU memory External Root of Trust failure | Yes |
| `Resource.Hpc.Unhealthy.GPUMemoryBWFailure` | GPU memory bandwidth failure | Yes |
| `Resource.Hpc.Unhealthy.CPUPerformance` | CPU performance issue | Yes |

### Choosing the Right Category

| Observed Issue | Category |
|---------------|----------|
| GPU not visible in nvidia-smi | `HpcMissingGpu` |
| IB port shows carrier=-1, won't come up after reboot | `IBPortDown` |
| IB port carrier_changes count is high | `IBPortFlapping` |
| IB bandwidth test consistently degraded | `IBPerformance` |
| IB interface completely missing | `MissingIB` |
| dcgmi diag -r 3 fails | `HpcGpuDcgmDiagFailure` |
| Thermal throttling under load | `HpcDcgmiThermalReport` |
| XID 79 in dmesg (GPU fallen off bus) | `XID79FallenOffBus` |
| XID 94 in dmesg (contained ECC error) | `XID94ContainedECCError` |
| XID 95 in dmesg (uncontained ECC error) | `XID95UncontainedECCError` |
| XID 48 in dmesg (double-bit ECC) | `XID48DoubleBitECC` |
| Other XID errors | `GpuXIDError` |
| nvidia-smi hangs or crashes | `UnhealthyGPUNvidiasmi` |
| NVLink down / FabricManager errors / ClusterUUID all zeros | `NvLink` |
| GPU row remap failure | `HpcRowRemapFailure` |
| GPU infoROM corruption | `HpcInforomCorruption` |
| None of the above fits | `HpcGenericFailure` |
| Need Azure HPC team to investigate | `ManualInvestigation` |

## REST API Format

### Endpoint

```
PUT https://management.azure.com/subscriptions/{subscriptionId}/providers/Microsoft.Impact/workloadImpacts/{workloadImpactName}?api-version=2023-02-01-preview
```

- `{subscriptionId}`: The subscription onboarded to GHR.
- `{workloadImpactName}`: A unique identifier (use a GUID).

### Request Body

```json
{
  "properties": {
    "startDateTime": "2025-01-15T12:00:00Z",
    "reportedTimeUtc": "2025-01-15T12:05:00Z",
    "impactCategory": "Resource.Hpc.Unhealthy.IBPortDown",
    "impactDescription": "IB port ib2 down on ccw-gpu-5. Persists after reboot. ibstat shows State: Down, Physical state: Polling.",
    "impactedResourceId": "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/myRG/providers/Microsoft.Compute/virtualMachines/ccw-gpu-5",
    "additionalProperties": {
      "PhysicalHostName": "GGBB90904476",
      "VmUniqueId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    }
  }
}
```

### Using az CLI

```bash
az rest --method PUT \
  --headers "Content-Type=application/json" \
  --url "https://management.azure.com/subscriptions/${SUB_ID}/providers/Microsoft.Impact/workloadImpacts/$(uuidgen)?api-version=2023-02-01-preview" \
  --body '{
    "properties": {
      "startDateTime": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      "reportedTimeUtc": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      "impactCategory": "Resource.Hpc.Unhealthy.IBPortDown",
      "impactDescription": "IB port ib2 down on ccw-gpu-5 after reboot",
      "impactedResourceId": "/subscriptions/.../virtualMachines/ccw-gpu-5",
      "additionalProperties": {
        "PhysicalHostName": "GGBB90904476"
      }
    }
  }'
```

### Additional Properties for GPU Issues

For GPU-related categories, include these optional fields to speed up recovery:

```json
"additionalProperties": {
  "PhysicalHostName": "GGBB90904476",
  "VmUniqueId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "Manufacturer": "NVIDIA",
  "SerialNumber": "1234567890",
  "ModelNumber": "GB300",
  "Location": "00000000:C9:00.0",
  "LogUrl": "https://..."
}
```

### Row Remap Fields

For `HpcRowRemapFailure`, include row remap details:

```json
"additionalProperties": {
  "PhysicalHostName": "GGBB90904476",
  "UCE": "3",
  "SerialNumber": "1234567890"
}
```

## Querying GHR Status (Insights)

After submitting a GHR, poll for insights to track progress:

```bash
GET "https://management.azure.com/subscriptions/{subscriptionId}/providers/Microsoft.Impact/workloadImpacts/{impactId}/insights?api-version=2025-01-01-preview"
```

### Insight Status Codes

| statusCode | terminalInsight | Meaning |
|-----------|:-:|---------|
| `AcknowledgedUnhealthy` | false | Azure acknowledged the report; investigation in progress |
| `NodeRemovedFromService` | true | Node removed for repair; expect replacement |
| `TooManyRequests` | true | Rate limited — wait before resubmitting |

### Interpreting Insights

Insights arrive as a sequence. Check `additionalDetails.terminalInsight`:
- `false` — still being processed, check again later.
- `true` — final state, no more updates coming.

## Workflow Summary

1. **Detect issue** (via NCCL test, GPU test, healthcheck, user report).
2. **Collect metadata** — PhysicalHostName + Resource ID (BEFORE any reboot).
3. **Attempt soft fix** — reboot the node (unless it's FabricManager/XID79/XID95).
4. **If issue persists after reboot** — drain the node in Slurm.
5. **File GHR** — use the correct impact category, include PhysicalHostName and all available GPU details.
6. **Poll insights** — monitor for acknowledgment and resolution.
7. **After Azure repairs/replaces** — the node will return with new hardware. Undrain and re-validate.
