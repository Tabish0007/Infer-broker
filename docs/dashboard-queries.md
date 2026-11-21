# Grafana panels (build these four — do not import a generic dashboard)

Open Grafana → Dashboards → New → add panel → paste PromQL.

### 1. Cost per 1M tokens, by team
```promql
sum by (team) (
  increase(kube_pod_container_resource_requests{resource="nvidia.com/gpu"}[$__range])
) / 3600 * 1.00
/
sum by (team) (increase(vllm:generation_tokens_total[$__range]) / 1e6)
```
Unit: `currency:EUR`. This is the panel that goes in the README screenshot.

### 2. GPU-hours requested vs. tokens generated (efficiency)
```promql
sum by (team) (increase(kube_pod_container_resource_requests{resource="nvidia.com/gpu"}[$__range])) / 3600
```
Overlay: `sum by (team) (increase(vllm:generation_tokens_total[$__range]) / 1e6)`

### 3. Cold start p50 / p95
```promql
histogram_quantile(0.5,  sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))
histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))
```

### 4. Queue pressure (Kueue)
```promql
sum(kueue_pending_workloads)
```
Alert idea: pending > 0 for 10m on `interactive` priority → page.

### Bonus: unattributed GPU spend (the panel that sells the platform)
```promql
sum(kube_pod_container_resource_requests{resource="nvidia.com/gpu"})
- sum(kube_pod_container_resource_requests{resource="nvidia.com/gpu", team!=""})
```
Every company has this number and it is never zero.
