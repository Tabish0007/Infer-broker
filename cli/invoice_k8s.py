#!/usr/bin/env python3
"""Chargeback from the Kubernetes API, not Prometheus.

Why: a billing number must not depend on the observability stack being healthy.
The Kubernetes API is the source of truth for allocation:
    pod runtime x requested GPUs = GPU-hours
Throughput (tokens) is scraped from the exporter directly.

Trade-off, stated plainly: this measures ALLOCATED capacity, not UTILISED
capacity. A pod holding 2 GPUs and idling costs 2 GPUs. That matches the
reserved-not-consumed model in ADR 0004, so both paths agree.
"""
import argparse
import datetime
import json
import os
import subprocess
import sys
import urllib.request

GPU_EUR = float(os.getenv("GPU_HOURLY_EUR", "1.00"))
CPU_EUR = float(os.getenv("CPU_HOURLY_EUR", "0.04"))


def parse_cpu(v):
    v = str(v or "0")
    if v.endswith("m"):
        return float(v[:-1]) / 1000.0
    if v.endswith("n"):
        return float(v[:-1]) / 1e9
    return float(v)


def get_pods(ns):
    out = subprocess.run(
        ["kubectl", "-n", ns, "get", "pods", "-o", "json"],
        capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(out)["items"]


def end_time(pod):
    """Finished pods stop accruing cost; running pods accrue to now."""
    now = datetime.datetime.now(datetime.timezone.utc)
    if pod["status"].get("phase") in ("Succeeded", "Failed"):
        stamps = [
            cs.get("state", {}).get("terminated", {}).get("finishedAt")
            for cs in pod["status"].get("containerStatuses", [])
        ]
        stamps = [s for s in stamps if s]
        if stamps:
            return datetime.datetime.fromisoformat(max(stamps).replace("Z", "+00:00"))
    return now


def hours_for(pod, cap_hours):
    start = pod["status"].get("startTime")
    if not start:
        return 0.0
    t0 = datetime.datetime.fromisoformat(start.replace("Z", "+00:00"))
    hrs = (end_time(pod) - t0).total_seconds() / 3600.0
    return max(0.0, min(hrs, cap_hours))


def requests_of(pod):
    gpu, cpu = 0, 0.0
    for c in pod["spec"].get("containers", []):
        req = (c.get("resources") or {}).get("requests") or {}
        gpu += int(float(req.get("nvidia.com/gpu", 0) or 0))
        cpu += parse_cpu(req.get("cpu", 0))
    return gpu, cpu


def scrape_tokens(url, team):
    total = 0.0
    with urllib.request.urlopen(url, timeout=5) as r:
        body = r.read().decode()
    for line in body.splitlines():
        if not line or line.startswith("#"):
            continue
        if line.startswith("vllm:generation_tokens_total"):
            if f'team="{team}"' not in line:
                continue
            total += float(line.rsplit(" ", 1)[1])
    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--team", required=True)
    ap.add_argument("--window", default="1h")
    ap.add_argument("--app-url", default=None,
                    help="exporter URL, e.g. http://localhost:8080/metrics")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    cap = int(a.window[:-1]) * {"s": 1/3600, "m": 1/60, "h": 1, "d": 24}[a.window[-1]]

    rows = []
    gpu_hours = cpu_hours = 0.0
    for pod in get_pods(a.team):
        gpu, cpu = requests_of(pod)
        h = hours_for(pod, cap)
        if h <= 0:
            continue
        rows.append((pod["metadata"]["name"], gpu, cpu, h))
        gpu_hours += gpu * h
        cpu_hours += cpu * h

    tokens = 0.0
    token_src = "not queried"
    if a.app_url:
        try:
            tokens = scrape_tokens(a.app_url, a.team)
            token_src = a.app_url
        except Exception as e:                       # noqa: BLE001
            token_src = f"unavailable ({e.__class__.__name__})"

    gpu_cost = gpu_hours * GPU_EUR
    cpu_cost = cpu_hours * CPU_EUR
    total = gpu_cost + cpu_cost
    per_m = (total / (tokens / 1e6)) if tokens else None

    if a.json:
        print(json.dumps({
            "team": a.team, "window": a.window,
            "pods": [{"pod": n, "gpus": g, "cpu": c, "hours": round(h, 4)}
                     for n, g, c, h in rows],
            "gpu_hours": round(gpu_hours, 4), "cpu_core_hours": round(cpu_hours, 4),
            "tokens": round(tokens, 2), "cost_eur": round(total, 4),
            "cost_per_million_tokens_eur": round(per_m, 4) if per_m else None,
            "token_source": token_src,
        }, indent=2))
        return 0

    print(f"# Invoice — `{a.team}`")
    print(f"Period: last {a.window} (capped per pod) · generated {datetime.date.today()}\n")
    print("## Allocation")
    print("| Pod | GPUs | CPU | Runtime (h) | GPU-hours |")
    print("|---|---|---|---|---|")
    for n, g, c, h in sorted(rows, key=lambda r: -r[3])[:12]:
        print(f"| `{n}` | {g} | {c:g} | {h:.3f} | {g * h:.3f} |")
    print()
    print("## Charges")
    print("| Line item | Quantity | Rate | Cost |")
    print("|---|---|---|---|")
    print(f"| GPU-hours | {gpu_hours:.3f} | €{GPU_EUR:.2f}/h | €{gpu_cost:.2f} |")
    print(f"| CPU core-hours | {cpu_hours:.3f} | €{CPU_EUR:.3f}/h | €{cpu_cost:.2f} |")
    print(f"| **Total** | | | **€{total:.2f}** |\n")
    print(f"**Completion tokens served:** {tokens:,.0f}  _(source: {token_src})_")
    print(f"**Cost per 1M tokens:** " + (f"€{per_m:.4f}" if per_m else "n/a"))
    print("\n> Allocated capacity, not utilised. Pricing explicit. See `docs/adr/0004`.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
