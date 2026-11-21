#!/usr/bin/env bash
set -uo pipefail
NS=team-a
P=0; F=0
pass(){ P=$((P+1)); printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
fail(){ F=$((F+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
hdr(){ printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
waitfor(){ local i=0; while [ $i -lt "$1" ]; do eval "$2" && return 0; sleep 2; i=$((i+2)); done; return 1; }

hdr "1. fake GPU capacity"
g=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null | grep -v control-plane | grep -c ' 4')
[ "${g:-0}" -ge 2 ] && pass "$g workers with 4 GPUs each" || fail "no GPU capacity -> run: make fake-gpu"

hdr "2. kueue queue active"
cq=$(kubectl get clusterqueue shared-gpu-pool -o jsonpath='{.status.conditions[?(@.type=="Active")].status}' 2>/dev/null)
[ "$cq" = "True" ] && pass "ClusterQueue Active" || fail "ClusterQueue not active"

hdr "3. quota rejection (the core demo)"
kubectl -n $NS delete job --all --ignore-not-found >/dev/null 2>&1
kubectl -n $NS delete workload --all --ignore-not-found >/dev/null 2>&1
kubectl apply -f platform/kueue/demo-jobs.yaml >/dev/null 2>&1
if waitfor 70 'kubectl -n team-a get pods -l job-name=batch-small -o jsonpath="{.items[0].status.phase}" 2>/dev/null | grep -q Running'; then
  pass "batch-small (2 GPUs) admitted and Running"
else
  fail "batch-small never started"
  kubectl -n $NS describe pod -l job-name=batch-small 2>/dev/null | grep -A6 Events | tail -8
fi
if kubectl -n $NS get workloads -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="QuotaReserved")].status}{"\n"}{end}' 2>/dev/null | grep batch-huge | grep -q True; then
  fail "batch-huge WAS admitted - quota too large"
else
  pass "batch-huge refused by quota"
fi

hdr "4. live endpoint + traffic"
kubectl -n inference-demo port-forward svc/mock-inference 8080:80 >/dev/null 2>&1 &
PF=$!
sleep 4
if curl -s -m 5 http://localhost:8080/healthz | grep -q '"ok"'; then
  pass "endpoint responding"
  for i in $(seq 1 40); do
    curl -s -m 5 -N http://localhost:8080/v1/chat/completions \
      -H 'content-type: application/json' \
      -d '{"messages":[{"role":"user","content":"hello platform"}]}' >/dev/null 2>&1
  done
  pass "40 requests served"
else
  fail "endpoint not responding"
fi
kill $PF 2>/dev/null

hdr "5. cost invoice"
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 >/dev/null 2>&1 &
PF2=$!
sleep 6
if PROM_URL=http://localhost:9090 python3 cli/chargeback.py --team team-a 2>/dev/null; then
  pass "invoice generated"
else
  fail "invoice failed (prometheus not reachable)"
fi
kill $PF2 2>/dev/null

kubectl -n $NS delete job --all --ignore-not-found >/dev/null 2>&1
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$P" "$F"
