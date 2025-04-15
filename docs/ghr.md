# Guest Health Reporting (GHR)

Guest Health Reporting (GHR) is a mechanism that allows customers to notify Azure about suspected hardware issues with specific nodes. It is available to approved customers operating supported VM SKUs like NDv4 and NDv5.

## 1. What is GHR?

GHR enables external users to flag potentially faulty virtual machines to Microsoft. These reports contribute to Azure's hardware telemetry and support processes, accelerating detection and remediation of underlying issues.

## 2. Who Can Use GHR?

GHR is currently in preview and is only available to approved customers. To request access:

- Register the `Microsoft.Impact` resource provider
- Enable the preview feature `Allow Impact Reporting`
- Assign the `Impact Reporter` role to your reporting identity
- Complete the onboarding form (link in [Getting Started](getting-started.md))

## 3. How GHR Works

Once enabled:

1. You detect a node with a suspected fault (via validation, logs, repeated failures, etc.)
2. Your system (or you) sends a signed POST request to the GHR API with impact details
3. Azure logs and triages the report; correlated reports trigger deeper diagnostics or node removal

Reports are not immediate triggers—they are signals in a broader telemetry system.

## 4. Reporting an Impact

To report an impact, POST to the following endpoint:

```
https://impact.api.azure.com/impact/v1/report
```

With a body like:

```json
{
  "subscriptionId": "<your-subscription-id>",
  "resourceUri": "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/<vm-name>",
  "impactedComponents": [
    {
      "impactCategory": "GPU",
      "impactType": "DegradedPerformance",
      "timestamp": "2024-04-10T22:30:00Z"
    }
  ]
}
```

Make sure your identity has the `Impact Reporter` role and your app is registered in Azure AD.

## 5. Supported Impact Categories

| Category | Type                | Example                          |
|----------|---------------------|----------------------------------|
| GPU      | DegradedPerformance | ECC errors, frequent resets      |
| IB       | Unreachable         | Node fails NCCL or link tests    |
| CPU      | UnexpectedReboot    | Node crashes during workload     |
| PCIe     | BandwidthThrottle   | PCIe/NVLink bottleneck observed  |

## 6. Best Practices

- Only report when confident the issue is hardware-related
- Include timestamps and context if possible
- Integrate into automated diagnostic pipelines for scale

---

Next: [InfiniBand Topology](topology.md)
