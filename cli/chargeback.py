#!/usr/bin/env python3
"""Per-team cost invoice from Prometheus.

Two things this file gets right on purpose:
  * CPU/tokens are counters -> increase() over the window.
  * GPU requests are a GAUGE (constant while a pod lives) -> avg_over_time()
    times the window length gives GPU-hours. increase() on a gauge is 0.
All queries filter by NAMESPACE, not by a `team` label, because Kubernetes
metrics do not have one. The app metric does, and is filtered by it.
"""
import argparse
import datetime
import json
import os
import sys
import urllib.parse
import urllib.request

PROM = os.getenv("PROM_URL", "http://localhost:9090")
PRICES = {
    "gpu_hour": float(os.getenv("GPU_HOURLY_EUR", "1.00")),
    "cpu_core_hour": float(os.getenv("CPU_HOURLY_EUR", "0.04")),
}


def query(expr):
    url = f"{PROM}/api/v1/query?query={urllib.parse.quote(expr)}"
    with urllib.request.urlopen(url, timeout=15) as r:
        payload = json.load(r)
    if payload.get("status") != "success":
        raise RuntimeError(payload)
    return payload["data"]["result"]


def scalar(expr):
    res = query(expr)
    return float(res[0]["value"][1]) if res else 0.0


def window_hours(w):
    mult = {"s": 1, "m": 60, "h": 3600, "d": 86400}
    return int(w[:-1]) * mult[w[-1]] / 3600.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--team", required=True)
    ap.add_argument("--window", default="1h")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--debug", action="store_true")
    a = ap.parse_args()

    hours = window_hours(a.window)

    q_tokens = (f'sum(increase(vllm:generation_tokens_total'
                f'{{team="{a.team}"}}[{a.window}]))')
    q_gpu = (f'sum(avg_over_time(kube_pod_container_resource_requests'
             f'{{namespace="{a.team}", resource="nvidia.com/gpu"}}[{a.window}]))')
    q_cpu = (f'sum(increase(container_cpu_usage_seconds_total'
             f'{{namespace="{a.team}", container!=""}}[{a.window}]))')

    tokens = scalar(q_tokens)
    gpu_avg = scalar(q_gpu)
    gpu_hours = gpu_avg * hours
    cpu_hours = scalar(q_cpu) / 3600.0

    gpu_cost = gpu_hours * PRICES["gpu_hour"]
    cpu_cost = cpu_hours * PRICES["cpu_core_hour"]
    total = gpu_cost + cpu_cost
    per_million = (total / (tokens / 1e6)) if tokens else None

    if a.debug:
        for name, q in (("tokens", q_tokens), ("gpu", q_gpu), ("cpu", q_cpu)):
            print(f"[debug] {name}: {len(query(q))} series")
            print(f"        {q}", file=sys.stderr)

    if a.json:
        print(json.dumps({
            "team": a.team, "window": a.window,
            "tokens": round(tokens, 2),
            "gpu_avg_allocated": round(gpu_avg, 3),
            "gpu_hours": round(gpu_hours, 4),
            "cpu_core_hours": round(cpu_hours, 4),
            "cost_eur": round(total, 4),
            "cost_per_million_tokens_eur": round(per_million, 4) if per_million else None,
        }, indent=2))
        return 0

    print(f"# Invoice — `{a.team}`")
    print(f"Period: last {a.window} · generated {datetime.date.today()}\n")
    print("| Line item | Quantity | Rate | Cost |")
    print("|---|---|---|---|")
    print(f"| GPU-hours | {gpu_hours:.2f} | €{PRICES['gpu_hour']:.2f}/h | €{gpu_cost:.2f} |")
    print(f"| CPU core-hours | {cpu_hours:.2f} | €{PRICES['cpu_core_hour']:.3f}/h | €{cpu_cost:.2f} |")
    print(f"| **Total** | | | **€{total:.2f}** |\n")
    print(f"**Completion tokens served:** {tokens:,.0f}")
    if per_million:
        print(f"**Cost per 1M tokens:** €{per_million:.4f}")
    else:
        print("**Cost per 1M tokens:** n/a (no generation traffic in window)")
    print(f"**Average GPUs allocated:** {gpu_avg:.2f}")
    print("\n> Pricing model is explicit, not derived. See `docs/adr/0004`.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
