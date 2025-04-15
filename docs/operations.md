# Operations

This section covers best practices for day-to-day operations of Azure GPU supercomputing clusters, including workload monitoring, failure remediation, and using Guest Health Reporting (GHR).

## 1. Monitoring Jobs and Node Health

For job-level and cluster-level visibility:

- Use Prometheus and Grafana for GPU/CPU/memory metrics
- Monitor GPU utilization, thermal state, ECC errors, and memory usage via `nvidia-smi` or DCGM
- InfiniBand traffic and errors can be tracked using `perfquery`, `ibdiagnet`, or `infiniband-exporter`
- Use AzHPC telemetry or Moneo if supported in your cluster

## 2. Common Failure Modes

Watch for:

- Node hangs or unresponsiveness
- Repeated job failures on specific nodes
- ECC or PCIe errors
- GPUs missing from `nvidia-smi`
- InfiniBand degradation or disconnections

Many of these are detected during pre-job NHC or post-failure diagnostics.

## 3. Failure Remediation

Steps:

1. **Drain the node** from your scheduler (e.g., `scontrol update nodename=XXX state=drain reason="validation fail"`).
2. Run AzHPC NHC or custom diagnostics scripts.
3. Compare results with historical telemetry.
4. If issue persists and GHR is enabled, report it.

Document steps and timestamps to correlate with Azure support logs if escalation is required.

## 4. Node Reallocation

If you observe flaky behavior (intermittent failures), consider:

- Manually deallocating and reallocating the node
- Reimaging the node with your base image
- Cross-validating in different jobs or under stress testing

Avoid building long-term automation around reallocation—it’s a workaround, not a fix.

## 5. Guest Health Reporting (GHR)

For supported customers, GHR enables impact reporting and tracking hardware incidents.

- Register using the onboarding steps in [Getting Started](getting-started.md)
- For full usage, see [GHR](ghr.md)

GHR can be integrated with job failure detection systems to auto-report problematic nodes.

---

Next: [Guest Health Reporting (GHR)](ghr.md)
