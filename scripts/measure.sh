#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
TEAM=team-a

echo "== removing old deployment from inference-demo"
kubectl -n inference-demo delete deploy mock-inference --ignore-not-found >/dev/null 2>&1
kubectl -n inference-demo delete svc  mock-inference --ignore-not-found >/dev/null 2>&1

echo "== deploying into namespace $TEAM"
make workload NAMESPACE=$TEAM TEAM=$TEAM >/dev/null
kubectl -n $TEAM rollout status deploy/mock-inference --timeout=120s || kubectl -n $TEAM get pods

echo "== service monitor"
kubectl apply -f platform/observability/servicemonitor.yaml

echo "== starting GPU job (so GPU-hours is non-zero)"
kubectl -n $TEAM delete job --all --ignore-not-found >/dev/null 2>&1
kubectl apply -f platform/kueue/demo-jobs.yaml >/dev/null
sleep 10
kubectl -n $TEAM get pods --no-headers | head -4

echo "== generating traffic"
kubectl -n $TEAM port-forward svc/mock-inference 8080:80 >/dev/null 2>&1 & PF=$!
sleep 4
for i in $(seq 1 100); do
  curl -s -m 5 -N http://localhost:8080/v1/chat/completions \
    -H 'content-type: application/json' \
    -d '{"messages":[{"role":"user","content":"hello platform"}]}' >/dev/null 2>&1
done
kill $PF 2>/dev/null
echo "   100 requests sent"

echo "== waiting for scrape + ingestion"
sleep 25

echo "== prometheus diagnostics"
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9091:9090 >/dev/null 2>&1 & PFP=$!
sleep 5
q(){ curl -s -G "http://localhost:9091/api/v1/query" --data-urlencode "query=$1" \
  | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print("   series:",len(r), [x["metric"] for x in r][:2])' 2>/dev/null || echo "   query failed"; }
echo " up{namespace=team-a}:";                     q 'up{namespace="team-a"}'
echo " vllm:generation_tokens_total:";             q 'vllm:generation_tokens_total'
echo " kube_pod_container_resource_requests:";     q 'kube_pod_container_resource_requests{namespace="team-a"}'
echo " container_cpu_usage_seconds_total:";        q 'container_cpu_usage_seconds_total{namespace="team-a"}'
kill $PFP 2>/dev/null

echo "== invoice"
./scripts/invoice.sh $TEAM 15m
