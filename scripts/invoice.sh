#!/usr/bin/env bash
set -uo pipefail
TEAM="${1:-team-a}"; WINDOW="${2:-15m}"; PORT="${3:-9090}"
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus "$PORT":9090 >/dev/null 2>&1 &
PF=$!
for i in $(seq 1 12); do
  curl -sf "http://localhost:$PORT/-/healthy" >/dev/null 2>&1 && break
  sleep 1
done
PROM_URL="http://localhost:$PORT" python3 "$(dirname "$0")/../cli/chargeback.py" --team "$TEAM" --window "$WINDOW"
kill $PF 2>/dev/null
