#!/usr/bin/env python3
"""
Collect Prometheus stats per benchmark run and break down by role.

For each results/conc-*/ dir:
  - Parse timings.txt to get BENCH_START..BENCH_END (UTC).
  - Parse pod-placement.tsv to map pod -> node -> role.
  - Query Prometheus for the window: GPU metrics (DCGM, by node->role) and
    container metrics (CPU/mem/network for frontend/etcd/nats and worker totals).
  - Write stats.json + stats.md to the results dir.

Scrape intervals on this cluster (verified via /api/v1/targets):
  nvidia-dcgm-exporter = 15s   -> step=15 below matches native cadence.
  kubelet / cAdvisor   = 30s   -> rate windows are [1m] (>= 2 scrapes).
"""
from __future__ import annotations
import csv
import json
import re
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from statistics import mean

PROM = "http://localhost:9090"
RESULTS_ROOT = Path(__file__).resolve().parent.parent / "results"

def parse_ts(s: str) -> int:
    return int(datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())


def prom_query_range(query: str, start: int, end: int, step: int = 15):
    qs = urllib.parse.urlencode({"query": query, "start": start, "end": end, "step": step})
    url = f"{PROM}/api/v1/query_range?{qs}"
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)["data"]["result"]


def values_only(series_list):
    out = []
    for s in series_list:
        vals = [float(v[1]) for v in s.get("values", []) if v[1] not in ("NaN", "+Inf", "-Inf")]
        if vals:
            out.append((s["metric"], vals))
    return out


def stat(values):
    if not values:
        return {"n": 0, "mean": None, "p50": None, "p99": None, "min": None, "max": None}
    vs = sorted(values)
    n = len(vs)
    return {
        "n": n,
        "mean": round(mean(vs), 2),
        "p50": round(vs[n // 2], 2),
        "p99": round(vs[min(n - 1, int(n * 0.99))], 2),
        "min": round(vs[0], 2),
        "max": round(vs[-1], 2),
    }


def aggregate(series_list, by_label=None):
    if by_label is None:
        all_vals = []
        for _, vals in series_list:
            all_vals.extend(vals)
        return stat(all_vals)
    groups = {}
    for labels, vals in series_list:
        key = labels.get(by_label, "?")
        groups.setdefault(key, []).extend(vals)
    return {k: stat(v) for k, v in groups.items()}


# --- per-run pipeline --------------------------------------------------------

def parse_timings(p: Path):
    events = {}
    with p.open() as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) >= 2:
                events.setdefault(parts[1], parts[0])
    return events


def parse_placement(p: Path):
    node_roles = {}
    pod_role = []
    with p.open() as f:
        rdr = csv.DictReader(f, delimiter="\t")
        for row in rdr:
            pod, role, node, gpu = row["pod"], row["role"], row["node"], row.get("gpu_indices", "-")
            pod_role.append((pod, role, node, gpu))
            if "worker" in role:
                short = "prefill" if role.startswith("prefill") else "decode"
                node_roles.setdefault(node, set()).add(short)
    return node_roles, pod_role


def role_label_filter(node_roles, target_role):
    nodes = sorted(n for n, roles in node_roles.items() if target_role in roles and len(roles) == 1)
    return "|".join(nodes), nodes


def collect_run(results_dir: Path):
    timings = parse_timings(results_dir / "timings.txt")
    bench_start = timings.get("BENCH_START")
    bench_end = timings.get("BENCH_END")
    if not bench_start or not bench_end:
        print(f"  {results_dir.name}: no BENCH_START/END, skip", file=sys.stderr)
        return None
    start, end = parse_ts(bench_start), parse_ts(bench_end)
    if end - start < 30:
        # too short for a 15s step; widen window slightly
        end = start + 60

    placement = results_dir / "pod-placement.tsv"
    if not placement.exists():
        print(f"  {results_dir.name}: no pod-placement.tsv, skip", file=sys.stderr)
        return None
    node_roles, pod_role = parse_placement(placement)

    prefill_re, prefill_nodes = role_label_filter(node_roles, "prefill")
    decode_re, decode_nodes = role_label_filter(node_roles, "decode")
    # nodes hosting BOTH prefill and decode workers
    mixed_nodes = sorted(n for n, roles in node_roles.items() if len(roles) > 1)
    mixed_re = "|".join(mixed_nodes)

    out = {
        "run": results_dir.name,
        "bench_start_utc": bench_start,
        "bench_end_utc": bench_end,
        "duration_s": end - start,
        "node_roles": {n: sorted(r) for n, r in node_roles.items()},
        "prefill_nodes": prefill_nodes,
        "decode_nodes": decode_nodes,
        "mixed_nodes": mixed_nodes,
        "gpu": {},
        "container": {},
    }

    # --- GPU metrics per role ----
    gpu_metrics = [
        ("util_pct", "DCGM_FI_DEV_GPU_UTIL"),
        ("power_w", "DCGM_FI_DEV_POWER_USAGE"),
        ("mem_used_mib", "DCGM_FI_DEV_FB_USED"),
        ("sm_clock_mhz", "DCGM_FI_DEV_SM_CLOCK"),
        ("nvlink_bw_kbps", "DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL"),
        ("tensor_active", "DCGM_FI_PROF_PIPE_TENSOR_ACTIVE"),
        ("dram_active", "DCGM_FI_PROF_DRAM_ACTIVE"),
        ("gpu_temp_c", "DCGM_FI_DEV_GPU_TEMP"),
        ("mem_temp_c", "DCGM_FI_DEV_MEMORY_TEMP"),
    ]
    for short, m in gpu_metrics:
        out["gpu"][short] = {}
        for role_name, role_re in [("prefill", prefill_re), ("decode", decode_re), ("mixed", mixed_re)]:
            if not role_re:
                out["gpu"][short][role_name] = stat([])
                continue
            q = f'{m}{{Hostname=~"{role_re}"}}'
            series = values_only(prom_query_range(q, start, end))
            out["gpu"][short][role_name] = aggregate(series)

    # --- Container metrics for support pods ----
    # Frontend/etcd/nats: rate of CPU + working_set memory + network
    support_pods = {
        "frontend": "inferencex-frontend.*",
        "etcd": "inferencex-etcd-.*",
        "nats": "inferencex-nats-.*",
    }
    for label, pod_re in support_pods.items():
        out["container"][label] = {}
        # CPU cores (rate over 1m)
        q_cpu = f'sum(rate(container_cpu_usage_seconds_total{{namespace="inferencex",pod=~"{pod_re}",container!="POD",container!=""}}[1m]))'
        series = values_only(prom_query_range(q_cpu, start, end))
        out["container"][label]["cpu_cores"] = aggregate(series)
        # Working-set memory bytes
        q_mem = f'sum(container_memory_working_set_bytes{{namespace="inferencex",pod=~"{pod_re}",container!="POD",container!=""}})'
        series = values_only(prom_query_range(q_mem, start, end))
        out["container"][label]["mem_mib"] = {"mean": None}
        s = aggregate(series)
        if s.get("mean") is not None:
            out["container"][label]["mem_mib"] = {k: (round(v / 1024 / 1024, 1) if isinstance(v, (int, float)) else v) for k, v in s.items()}
        # Network rx/tx in MB/s
        for direction in ("receive", "transmit"):
            q_net = f'sum(rate(container_network_{direction}_bytes_total{{namespace="inferencex",pod=~"{pod_re}"}}[1m]))'
            series = values_only(prom_query_range(q_net, start, end))
            s = aggregate(series)
            if s.get("mean") is not None:
                s = {k: (round(v / 1024 / 1024, 2) if isinstance(v, (int, float)) else v) for k, v in s.items()}
            out["container"][label][f"net_{direction}_mbps"] = s

    # Aggregate worker pod CPU/mem (prefill + decode separately)
    for role_name, pod_re in [("prefill_workers", "inferencex-prefill-.*-worker-.*"),
                              ("decode_workers", "inferencex-decode-.*-worker-.*")]:
        out["container"][role_name] = {}
        q_cpu = f'sum(rate(container_cpu_usage_seconds_total{{namespace="inferencex",pod=~"{pod_re}",container!="POD",container!=""}}[1m]))'
        series = values_only(prom_query_range(q_cpu, start, end))
        out["container"][role_name]["cpu_cores_total"] = aggregate(series)
        q_mem = f'sum(container_memory_working_set_bytes{{namespace="inferencex",pod=~"{pod_re}",container!="POD",container!=""}})'
        series = values_only(prom_query_range(q_mem, start, end))
        s = aggregate(series)
        if s.get("mean") is not None:
            s = {k: (round(v / 1024 / 1024 / 1024, 2) if isinstance(v, (int, float)) else v) for k, v in s.items()}
        out["container"][role_name]["mem_gib_total"] = s

    return out


# --- markdown rendering ------------------------------------------------------

def fmt(v):
    if v is None:
        return "—"
    if isinstance(v, float):
        return f"{v:.2f}".rstrip("0").rstrip(".")
    return str(v)


def render_md(stats: dict) -> str:
    lines = []
    lines.append(f"# Stats: {stats['run']}")
    lines.append("")
    lines.append(f"- Bench window: `{stats['bench_start_utc']}` → `{stats['bench_end_utc']}` ({stats['duration_s']}s)")
    lines.append(f"- Prefill nodes ({len(stats['prefill_nodes'])}): {', '.join(stats['prefill_nodes']) or '—'}")
    lines.append(f"- Decode nodes ({len(stats['decode_nodes'])}): {', '.join(stats['decode_nodes']) or '—'}")
    if stats['mixed_nodes']:
        lines.append(f"- Mixed nodes ({len(stats['mixed_nodes'])}): {', '.join(stats['mixed_nodes'])}")
    lines.append("")
    lines.append("## GPU metrics by role (mean / p50 / p99)")
    lines.append("")
    lines.append("| Metric | Prefill mean | Prefill p99 | Decode mean | Decode p99 |")
    lines.append("|---|---:|---:|---:|---:|")
    keys = [
        ("util_pct", "GPU util %"),
        ("tensor_active", "Tensor pipe active"),
        ("dram_active", "DRAM active"),
        ("power_w", "Power W"),
        ("sm_clock_mhz", "SM clock MHz"),
        ("mem_used_mib", "FB used MiB"),
        ("nvlink_bw_kbps", "NVLink kB/s"),
        ("gpu_temp_c", "GPU temp °C"),
        ("mem_temp_c", "HBM temp °C"),
    ]
    for k, label in keys:
        g = stats["gpu"].get(k, {})
        p = g.get("prefill", {})
        d = g.get("decode", {})
        lines.append(f"| {label} | {fmt(p.get('mean'))} | {fmt(p.get('p99'))} | {fmt(d.get('mean'))} | {fmt(d.get('p99'))} |")
    lines.append("")
    lines.append("## Support-pod load (mean over bench window)")
    lines.append("")
    lines.append("| Pod | CPU cores | RSS MiB | Net rx MB/s | Net tx MB/s |")
    lines.append("|---|---:|---:|---:|---:|")
    for label in ("frontend", "etcd", "nats"):
        c = stats["container"].get(label, {})
        cpu = c.get("cpu_cores", {}).get("mean")
        mem = c.get("mem_mib", {}).get("mean")
        rx = c.get("net_receive_mbps", {}).get("mean")
        tx = c.get("net_transmit_mbps", {}).get("mean")
        lines.append(f"| {label} | {fmt(cpu)} | {fmt(mem)} | {fmt(rx)} | {fmt(tx)} |")
    lines.append("")
    lines.append("## Worker pod aggregate load")
    lines.append("")
    lines.append("| Group | CPU cores total | RSS GiB total |")
    lines.append("|---|---:|---:|")
    for label in ("prefill_workers", "decode_workers"):
        c = stats["container"].get(label, {})
        cpu = c.get("cpu_cores_total", {}).get("mean")
        mem = c.get("mem_gib_total", {}).get("mean")
        lines.append(f"| {label.replace('_', ' ')} | {fmt(cpu)} | {fmt(mem)} |")
    lines.append("")
    return "\n".join(lines)


def main():
    runs = sorted(RESULTS_ROOT.glob("conc-*_2026*"))
    by_conc = {}
    for r in runs:
        m = re.match(r"(conc-\d+)_", r.name)
        if not m:
            continue
        by_conc[m.group(1)] = r  # keeps latest (sorted ascending, last wins)
    targets = sorted(by_conc.values(), key=lambda p: p.name)

    print(f"Processing {len(targets)} runs...")
    suite = []
    for r in targets:
        print(f"  {r.name}")
        s = collect_run(r)
        if not s:
            continue
        (r / "stats.json").write_text(json.dumps(s, indent=2))
        (r / "stats.md").write_text(render_md(s))
        suite.append(s)
    (RESULTS_ROOT / "suite-stats.json").write_text(json.dumps(suite, indent=2))
    print(f"Wrote {RESULTS_ROOT}/suite-stats.json")


if __name__ == "__main__":
    main()
