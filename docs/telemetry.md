# Telemetry & Observability

This section describes how to monitor the health and performance of your Azure supercomputing cluster using telemetry tools. Proper observability helps detect anomalies, prevent silent failures, and ensure peak utilization.

## 1. What to Monitor

Key system-level and job-level metrics include:

- **GPU metrics**: utilization, memory usage, ECC errors, temperature, throttling
- **CPU and memory usage**: saturation and NUMA behavior
- **InfiniBand**: throughput, link failures, retransmits
- **Node state**: availability, reboots, hangs
- **Scheduler state**: queue delays, idle GPUs, job eviction rates

## 2. Tools

You can use a combination of Azure-native, open-source, and AzHPC-provided tools.

### Moneo

Moneo is an Azure-native observability stack tailored for GPU clusters. It includes:

- Node exporter (Prometheus)
- NVIDIA DCGM exporter
- Infiniband exporter
- Pre-built Grafana dashboards

To deploy:

```bash
git clone https://github.com/Azure/moneo
cd moneo
./install.sh
```

It will deploy telemetry agents and set up a monitoring pipeline with Prometheus and Grafana.

### Prometheus + Grafana (Custom)

If you have an existing Prometheus setup, integrate exporters such as:

- `node_exporter`
- `dcgm-exporter`
- `infiniband-exporter`
- `slurm-exporter` (if using Slurm)

Use Grafana dashboards to correlate resource usage with job timing and errors.

## 3. Azure Monitoring (Optional)

You can also integrate with Azure Monitor or Log Analytics:

- Send custom logs and metrics using `telegraf`
- Use Azure Monitor Workbooks for dashboards
- Create alerts on hardware errors, GPU underutilization, or unexpected node reboots

## 4. Best Practices

- Tag all nodes by role (headnode, compute) for filtering
- Correlate telemetry with Slurm/Kubernetes logs
- Set up alerts for high ECC error rates or job starvation
- Archive telemetry from known-good clusters as performance baselines

---

Next: [Appendices](appendices.md)
