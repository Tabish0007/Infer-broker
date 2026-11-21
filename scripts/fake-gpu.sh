#!/usr/bin/env bash
# Advertise nvidia.com/gpu on kind worker nodes.
#
# There is no driver and no hardware. This patches status.allocatable so the
# kube-scheduler does REAL accounting against a fake quantity: pods requesting
# nvidia.com/gpu will be refused once the number is exhausted, exactly as with
# a real device plugin. Capacity resets if the node container restarts.
set -euo pipefail
GPUS_PER_NODE="${GPUS_PER_NODE:-4}"

for node in $(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o name | cut -d/ -f2); do
  kubectl patch node "$node" --subresource=status --type=merge -p "$(cat <<JSON
{"status":{"capacity":{"nvidia.com/gpu":"${GPUS_PER_NODE}"},
           "allocatable":{"nvidia.com/gpu":"${GPUS_PER_NODE}"}}}
JSON
)" >/dev/null
  echo "  patched $node -> nvidia.com/gpu=${GPUS_PER_NODE}"
done

echo
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
