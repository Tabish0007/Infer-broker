#!/usr/bin/env bash
set -uo pipefail
NS=team-a
b() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }

wl_for() {
  kubectl -n "$NS" get workloads.kueue.x-k8s.io -o name 2>/dev/null \
    | grep "job-$1-" | head -1 | cut -d/ -f2
}
cond() {
  local wl; wl=$(wl_for "$1")
  [ -z "$wl" ] && { echo "none"; return; }
  kubectl -n "$NS" get workload "$wl" \
    -o jsonpath="{.status.conditions[?(@.type==\"$2\")].status}" 2>/dev/null \
    | tr 'A-Z' 'a-z'
}
wait_reserved() {
  local i
  for i in $(seq 1 40); do
    [ "$(cond "$1" QuotaReserved)" = "true" ] && return 0
    sleep 1
  done
  return 1
}

b "Applying demo jobs"
kubectl apply -f platform/kueue/demo-jobs.yaml >/dev/null

b "1. batch-small requests 2 GPUs -- must reserve quota"
wait_reserved batch-small && echo "   QuotaReserved=true" || echo "   still pending"
kubectl -n "$NS" get job batch-small --no-headers
kubectl -n "$NS" get pods -o wide --no-headers | grep batch-small || true

b "2. batch-huge requests 16 GPUs -- must be refused, with a reason"
wait_reserved batch-huge && echo "   UNEXPECTED: reserved"
wl=$(wl_for batch-huge)
[ -n "$wl" ] && kubectl -n "$NS" get workload "$wl" \
  -o jsonpath='   reason: {.status.conditions[?(@.type=="QuotaReserved")].message}{"\n"}'

b "Cleanup"
kubectl -n "$NS" delete job batch-small batch-huge --ignore-not-found
