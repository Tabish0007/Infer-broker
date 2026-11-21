# Measurements

Run `make up`, generate traffic for 24h (or a compressed window, and say so),
then fill this in. **Every number needs a method and a date.**

```bash
# traffic generator
for i in $(seq 1 500); do
  curl -sN localhost:8080/v1/chat/completions \
    -H 'content-type: application/json' \
    -d '{"messages":[{"role":"user","content":"hello platform"}]}' >/dev/null
done
```

| Metric | Baseline | With platform | Method | Date |
|---|---|---|---|---|
| Cost per 1M generated tokens | €— | €— | panel 1 / `chargeback.py --json` | — |
| GPU-hours/week | 168 | — | `increase(kube_pod_container_resource_requests{resource="nvidia.com/gpu"}[1w])/3600` | — |
| Cold start p50 / p95 | — | — | `histogram_quantile` on TTFT | — |
| Team onboarding | ~2 days of tickets | — min | stopwatch | — |
| Queue pending time (batch) | — | — | `kueue_pending_workloads` | — |
| GPU utilisation | ~15% (est.) | — | **not measured** — needs DCGM | — |

## Notes
- GPU capacity is simulated (ADR 0006), so the baseline "168 GPU-hours/week" is a
  model, not a measurement. Labelled as such.
