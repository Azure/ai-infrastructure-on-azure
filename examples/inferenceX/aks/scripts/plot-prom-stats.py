#!/usr/bin/env python3
"""
Per-recipe Prometheus / DCGM plots, two-tier layout.

For each results/conc-*/ dir:

  1. ONE overview PNG  (`plots/overview.png`) -- 3x3 grid of all 9 metrics.
     Each subplot shows the **mean across GPUs per role** over time
     (prefill / decode / mixed / idle). Quick at-a-glance comparison.

  2. ONE detail PNG per (metric, active-role)  (`plots/<metric>__<role>.png`)
     Shows the spread across GPUs in that role:
       - thick line   = median
       - shaded band  = inter-quartile range (p25 - p75)
       - faint band   = min / max envelope
     This is the standard SRE / perf-dashboard idiom for non-Gaussian data:
     the median + IQR is robust to a single spiking GPU, while the min/max
     envelope still surfaces outliers (which is what you want to spot in a
     benchmark).

Sample cadence: STEP_S=15 matches the nvidia-dcgm-exporter ServiceMonitor
scrape interval on this cluster (verified via /api/v1/targets), so every
plotted point corresponds to one real DCGM scrape -- no down-sampling.

Outputs land under aks/results/conc-*/plots/, plus a top-level index
aks/results/plots-index.md cross-linking everything.

Usage:
  kubectl -n monitoring port-forward svc/kube-prometheus-kube-prome-prometheus 9090:9090 &
  python3 examples/inferenceX/aks/scripts/plot-prom-stats.py
"""
from __future__ import annotations
import csv
import json
import re
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

PROM = "http://localhost:9090"
RESULTS_ROOT = Path(__file__).resolve().parent.parent / "results"
STEP_S = 15  # matches DCGM scrape interval

METRICS = [
    ("gpu_util",       "DCGM_FI_DEV_GPU_UTIL",                "GPU util (%)"),
    ("tensor_active",  "DCGM_FI_PROF_PIPE_TENSOR_ACTIVE",     "Tensor pipe active"),
    ("dram_active",    "DCGM_FI_PROF_DRAM_ACTIVE",            "DRAM active"),
    ("power_w",        "DCGM_FI_DEV_POWER_USAGE",             "Power (W)"),
    ("sm_clock_mhz",   "DCGM_FI_DEV_SM_CLOCK",                "SM clock (MHz)"),
    ("fb_used_mib",    "DCGM_FI_DEV_FB_USED",                 "Frame-buffer used (MiB)"),
    ("nvlink_kbps",    "DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL",  "NVLink total (kB/s)"),
    ("gpu_temp_c",     "DCGM_FI_DEV_GPU_TEMP",                "GPU temp (\u00b0C)"),
    ("hbm_temp_c",     "DCGM_FI_DEV_MEMORY_TEMP",             "HBM temp (\u00b0C)"),
]

ROLE_COLOR = {
    "prefill": "#1f77b4",  # blue
    "decode":  "#d62728",  # red
    "mixed":   "#9467bd",  # purple
    "idle":    "#7f7f7f",  # grey
}
ROLE_ORDER = ["prefill", "decode", "mixed", "idle"]


# ---------------------------------------------------------------------------
# Prometheus + parsing helpers
# ---------------------------------------------------------------------------

def parse_ts(s: str) -> int:
    return int(datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())


def prom_query_range(query: str, start: int, end: int, step: int = STEP_S):
    qs = urllib.parse.urlencode({"query": query, "start": start, "end": end, "step": step})
    with urllib.request.urlopen(f"{PROM}/api/v1/query_range?{qs}", timeout=60) as r:
        return json.load(r)["data"]["result"]


def parse_timings(p: Path) -> dict[str, str]:
    events: dict[str, str] = {}
    with p.open() as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) >= 2:
                events.setdefault(parts[1], parts[0])
    return events


def parse_placement(p: Path) -> dict[str, set[str]]:
    node_roles: dict[str, set[str]] = {}
    with p.open() as f:
        for row in csv.DictReader(f, delimiter="\t"):
            role, node = row["role"], row["node"]
            if "worker" in role:
                short = "prefill" if role.startswith("prefill") else "decode"
                node_roles.setdefault(node, set()).add(short)
    return node_roles


def node_role(node_roles: dict[str, set[str]], node: str) -> str:
    roles = node_roles.get(node, set())
    if not roles:
        return "idle"
    if len(roles) > 1:
        return "mixed"
    return next(iter(roles))


def short_label(hostname: str, gpu_idx: str) -> str:
    m = re.search(r"vmss[0-9a-f]+", hostname)
    return f"{m.group(0) if m else hostname}:gpu{gpu_idx}"


# ---------------------------------------------------------------------------
# Series shaping: turn raw Prometheus result into (timestamps, matrix-by-role)
# ---------------------------------------------------------------------------

def shape_series(series: list, node_roles: dict[str, set[str]],
                 start: int, end: int, step: int = STEP_S):
    """
    Returns (ts, by_role) where:
      ts      = numpy array of UTC datetimes, one per scrape sample
      by_role = { role -> (matrix [n_gpus_in_role, n_samples], labels [n_gpus_in_role]) }
    Missing samples are NaN.
    """
    n_samples = (end - start) // step + 1
    ts_unix = np.arange(n_samples) * step + start
    ts = np.array([datetime.fromtimestamp(int(t), tz=timezone.utc) for t in ts_unix])

    by_role: dict[str, list[tuple[str, np.ndarray]]] = {r: [] for r in ROLE_ORDER}
    for s in series:
        host = s["metric"].get("Hostname", "?")
        gpu = s["metric"].get("gpu", "?")
        role = node_role(node_roles, host)
        label = short_label(host, gpu)

        row = np.full(n_samples, np.nan, dtype=float)
        for t_str, v_str in s["values"]:
            t = int(float(t_str))
            idx = (t - start) // step
            if 0 <= idx < n_samples and v_str not in ("NaN", "+Inf", "-Inf"):
                row[idx] = float(v_str)
        by_role[role].append((label, row))

    out: dict[str, tuple[np.ndarray, list[str]]] = {}
    for role, items in by_role.items():
        if not items:
            continue
        items.sort(key=lambda x: x[0])
        labels = [lbl for lbl, _ in items]
        mat = np.vstack([row for _, row in items])
        out[role] = (mat, labels)
    return ts, out


# ---------------------------------------------------------------------------
# Plotting
# ---------------------------------------------------------------------------

def _format_time_axis(ax):
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M:%S"))
    locator = mdates.AutoDateLocator(maxticks=6)
    locator.intervald[mdates.SECONDLY] = [5, 10, 15, 30]
    locator.intervald[mdates.MINUTELY] = [1, 2, 5, 10, 15, 30]
    ax.xaxis.set_major_locator(locator)


def plot_overview(ts: np.ndarray, all_metrics: dict[str, dict],
                  recipe_name: str, bench_start: str, bench_end: str,
                  out_path: Path) -> None:
    """3x3 grid; each cell shows mean-per-role line plot for one metric."""
    fig, axes = plt.subplots(3, 3, figsize=(18, 12), dpi=120, sharex=True)
    for ax_idx, (short, promql, title) in enumerate(METRICS):
        ax = axes[ax_idx // 3][ax_idx % 3]
        by_role = all_metrics[short]
        for role in ROLE_ORDER:
            if role not in by_role:
                continue
            mat, _labels = by_role[role]
            mean = np.nanmean(mat, axis=0)
            n = mat.shape[0]
            ax.plot(ts, mean, color=ROLE_COLOR[role],
                    linewidth=1.6, alpha=0.95,
                    label=f"{role} (n={n})")
        ax.set_title(title, fontsize=11)
        ax.grid(True, alpha=0.25)
        _format_time_axis(ax)
        if ax_idx % 3 == 0:
            ax.set_ylabel("value")
        if ax_idx == 0:
            ax.legend(fontsize=8, loc="best", frameon=False)

    fig.suptitle(
        f"{recipe_name} \u2014 mean per role across all 9 GPU metrics\n"
        f"BENCH {bench_start} \u2192 {bench_end}  (DCGM scrape = 15 s, no resampling)",
        fontsize=13,
    )
    fig.autofmt_xdate(rotation=0, ha="center")
    fig.tight_layout(rect=(0, 0, 1, 0.96))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


def plot_detail(ts: np.ndarray, mat: np.ndarray, labels: list[str],
                metric_title: str, role: str, recipe_name: str,
                bench_start: str, bench_end: str, out_path: Path) -> None:
    """
    Spread plot for one (metric, role).
    - thick line   = median
    - shaded band  = p25-p75 (IQR)
    - faint band   = min-max envelope
    """
    color = ROLE_COLOR[role]
    n = mat.shape[0]

    median = np.nanmedian(mat, axis=0)
    q25 = np.nanpercentile(mat, 25, axis=0)
    q75 = np.nanpercentile(mat, 75, axis=0)
    mn = np.nanmin(mat, axis=0)
    mx = np.nanmax(mat, axis=0)

    fig, ax = plt.subplots(figsize=(13, 6.0), dpi=120)

    # Min/max envelope (faintest)
    ax.fill_between(ts, mn, mx, color=color, alpha=0.10,
                    linewidth=0, label="min-max envelope")
    # IQR band
    ax.fill_between(ts, q25, q75, color=color, alpha=0.30,
                    linewidth=0, label="IQR (p25-p75)")
    # Median line
    ax.plot(ts, median, color=color, linewidth=2.2, alpha=0.95,
            label=f"median (n={n} GPUs)")

    ax.set_title(
        f"{recipe_name} \u2014 {metric_title}  [{role}]\n"
        f"BENCH {bench_start} \u2192 {bench_end}  (15 s scrape, raw)",
        fontsize=12,
    )
    ax.set_xlabel("UTC time")
    ax.set_ylabel(metric_title)
    ax.grid(True, alpha=0.25)
    _format_time_axis(ax)
    ax.legend(fontsize=9, loc="best", frameon=False)
    fig.autofmt_xdate(rotation=0, ha="center")
    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def collect_recipe(results_dir: Path) -> dict | None:
    timings = parse_timings(results_dir / "timings.txt")
    bench_start = timings.get("BENCH_START")
    bench_end = timings.get("BENCH_END")
    placement = results_dir / "pod-placement.tsv"
    if not (bench_start and bench_end and placement.exists()):
        return None

    start = parse_ts(bench_start)
    end = parse_ts(bench_end)
    if end - start < 30:
        end = start + 60
    pad = max(STEP_S, (end - start) // 20)
    start = (start - pad) // STEP_S * STEP_S
    end = ((end + pad + STEP_S - 1) // STEP_S) * STEP_S

    node_roles = parse_placement(placement)
    plots_dir = results_dir / "plots"

    # 1. Pull raw per-GPU series for every metric, shape into role-matrices
    all_metrics: dict[str, dict] = {}
    for short, promql, _title in METRICS:
        raw = prom_query_range(promql, start, end)
        ts, by_role = shape_series(raw, node_roles, start, end)
        all_metrics[short] = by_role
        all_metrics["__ts__"] = ts  # type: ignore[assignment]

    ts = all_metrics["__ts__"]  # type: ignore[assignment]
    plottable_metrics = {k: v for k, v in all_metrics.items() if k != "__ts__"}

    # 2. Overview (3x3 grid)
    overview_path = plots_dir / "overview.png"
    plot_overview(ts, plottable_metrics, results_dir.name,
                  bench_start, bench_end, overview_path)
    print(f"  wrote {overview_path.relative_to(RESULTS_ROOT.parent.parent.parent)}")

    # 3. Per-(metric, role) detail PNGs
    written = ["overview.png"]
    active_roles: set[str] = set()
    for by_role in plottable_metrics.values():
        for r in by_role:
            if r != "idle":  # idle has no signal worth a detail plot
                active_roles.add(r)

    for short, _promql, title in METRICS:
        by_role = plottable_metrics[short]
        for role in ROLE_ORDER:
            if role == "idle" or role not in by_role:
                continue
            mat, labels = by_role[role]
            out = plots_dir / f"{short}__{role}.png"
            plot_detail(ts, mat, labels, title, role,
                        results_dir.name, bench_start, bench_end, out)
            written.append(out.name)
    print(f"  wrote {len(written) - 1} detail PNGs across roles: {sorted(active_roles)}")

    return {
        "run": results_dir.name,
        "bench_start": bench_start,
        "bench_end": bench_end,
        "n_prefill_nodes": sum(1 for r in node_roles.values() if r == {"prefill"}),
        "n_decode_nodes": sum(1 for r in node_roles.values() if r == {"decode"}),
        "n_mixed_nodes": sum(1 for r in node_roles.values() if len(r) > 1),
        "active_roles": sorted(active_roles),
        "plots": written,
    }


def render_index(entries: list[dict]) -> str:
    L: list[str] = []
    L.append("# Per-recipe GPU utilization")
    L.append("")
    L.append("Per-role detail charts show **GPU utilization (%)** - the headline metric for "
             "spotting whether a role was actually busy. Per-recipe `plots/` directories also "
             "contain the full 9-metric breakdown (DCGM SM/DRAM/HBM/temp/power/fb) for "
             "deeper inspection.")
    L.append("")
    L.append("Plot encoding (detail charts):")
    L.append("")
    L.append("- thick line = **median** GPU util across the role")
    L.append("- shaded band = **IQR (p25-p75)** - middle 50% of GPUs")
    L.append("- faint band = **min-max envelope** - surfaces single-GPU outliers")
    L.append("")
    L.append("## Data granularity")
    L.append("")
    L.append("Verified against `/api/v1/targets?state=active` on this cluster's "
             "Prometheus (kube-prometheus-stack):")
    L.append("")
    L.append("| Source | Scrape interval | Used in |")
    L.append("|---|---|---|")
    L.append("| `nvidia-dcgm-exporter` | **15 s** | All 9 GPU plots (DCGM_FI_*) |")
    L.append("| `kubelet` / cAdvisor   | 30 s     | Container CPU / RSS / network tables |")
    L.append("| `node-exporter`        | 30 s     | (not plotted) |")
    L.append("| `kube-state-metrics`   | 30 s     | (not plotted) |")
    L.append("")
    L.append("The plotter samples at `STEP_S=15` to match DCGM's native cadence - every "
             "point corresponds to one real scrape (no aliasing, no resampling).")
    L.append("")
    L.append("## Re-generate")
    L.append("")
    L.append("```bash")
    L.append("kubectl -n monitoring port-forward svc/kube-prometheus-kube-prome-prometheus 9090:9090 &")
    L.append("python3 examples/inferenceX/aks/scripts/collect-prom-stats.py")
    L.append("python3 examples/inferenceX/aks/scripts/plot-prom-stats.py")
    L.append("```")
    L.append("")

    for e in sorted(entries, key=lambda x: int(re.match(r"conc-(\d+)_", x["run"]).group(1))):
        m = re.match(r"(conc-\d+)_", e["run"])
        title = m.group(1) if m else e["run"]
        L.append(f"## {title}")
        L.append("")
        L.append(f"- Bench window: `{e['bench_start']}` \u2192 `{e['bench_end']}`")
        topo = f"**{e['n_prefill_nodes']}** prefill nodes, **{e['n_decode_nodes']}** decode nodes"
        if e["n_mixed_nodes"]:
            topo += f", **{e['n_mixed_nodes']}** mixed"
        L.append(f"- Topology: {topo}")
        L.append(f"- Source dir: [`{e['run']}/`](./{e['run']}/)")
        L.append("")
        L.append("### Overview (mean per role, all 9 metrics)")
        L.append("")
        L.append(f"![overview](./{e['run']}/plots/overview.png)")
        L.append("")
        for role in e["active_roles"]:
            png = f"{e['run']}/plots/gpu_util__{role}.png"
            if (RESULTS_ROOT / png).exists():
                L.append(f"### GPU util \u2014 {role}")
                L.append("")
                L.append(f"![GPU util {role}](./{png})")
                L.append("")
        L.append("---")
        L.append("")
    return "\n".join(L)


def main() -> None:
    runs = sorted(RESULTS_ROOT.glob("conc-*_2026*"))
    by_conc: dict[str, Path] = {}
    for r in runs:
        m = re.match(r"(conc-\d+)_", r.name)
        if m:
            by_conc[m.group(1)] = r
    targets = sorted(by_conc.values(), key=lambda p: p.name)
    print(f"Plotting {len(targets)} recipes")
    entries: list[dict] = []
    for r in targets:
        print(f"\n{r.name}")
        e = collect_recipe(r)
        if e:
            entries.append(e)
    index_path = RESULTS_ROOT / "plots-index.md"
    index_path.write_text(render_index(entries))
    print(f"\nWrote index: {index_path}")


if __name__ == "__main__":
    main()
