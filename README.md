# gpu-platform

**Self-service GPU inference on Kubernetes with per-team chargeback.**

Teams get a namespace, a quota, and a model endpoint in one command. Finance gets a
cost-per-million-tokens number instead of a cloud bill and a shrug.

## Status

Verified on a local `kind` cluster: quota admission and refusal, priority classes,
allocation-based chargeback, and a live inference endpoint. GPU capacity is
simulated — see *What is simulated*. Nothing here is claimed that was not executed.

## The problem

A company buys eight GPUs. One team reserves them and uses 15%. Another team's job
is rejected while the pool sits idle. The bill arrives as one number with no
attribution, so everyone asks for more capacity and finance says no.

Quota alone cannot fix this: quota is a ceiling, not a share. This replaces the
ceiling with a queue, and adds attribution.

## What it does

| Layer | Implementation | Why |
|---|---|---|
| Tenancy | `cli/platform new-team` -> namespace, ResourceQuota, LimitRange, NetworkPolicy, LocalQueue | Onboarding is self-service, not a ticket |
| Admission | Kueue ClusterQueue + cohorts + WorkloadPriorityClass | Shared pool without starvation |
| Serving | OpenAI-compatible endpoint, scale-to-zero on idle | Idle capacity costs nothing |
| Chargeback | Per-pod allocation -> GPU-hours -> EUR invoice | The part nobody has |

## Results

Measured on kind, 2026-11-21, two workers advertising 4 simulated GPUs each.

| Check | Result |
|---|---|
| Job requesting 2 GPUs | Admitted, pod Running |
| Job requesting 16 GPUs (quota = 4) | Refused at admission: insufficient quota |
| Invoice for 2 GPUs x 0.05 h | **0.100 GPU-hours -> 0.10 EUR**, attributed to team-a |
| Live endpoint | Streaming SSE responses served |
| Environment check | 7 passed, 0 failed |

Not measured, and deliberately not invented: realised savings, cold-start latency
at scale, GPU utilisation (needs DCGM and real hardware).

## Quickstart

    make up            # kind + Kueue + observability + demo team
    make demo-quota    # admission / refusal
    make port-forward  # localhost:8080
    make invoice TEAM=team-a

## Design decisions

- [0001](docs/adr/0001-kueue-over-resourcequota.md) Kueue over plain ResourceQuota: ceiling vs share
- [0002](docs/adr/0002-karpenter-over-static-nodepools.md) Karpenter as production path, not exercised
- [0003](docs/adr/0003-scale-to-zero-breaks-streaming.md) Scale-to-zero truncates streams silently
- [0004](docs/adr/0004-chargeback-model.md) Chargeback: allocated GPU-hours, explicit pricing
- [0005](docs/adr/0005-no-service-mesh.md) Deliberately no service mesh
- [0006](docs/adr/0006-what-is-simulated.md) What is simulated, and why

ADR 0003 and 0007 are the two worth reading; both are about failure modes that look
like success in a dashboard.

## What is simulated

- **GPUs:** node `status.allocatable` is patched to advertise `nvidia.com/gpu: 4`.
  No driver, no hardware. The scheduler's accounting is real: pods are refused when
  capacity runs out.
- **Inference:** a CPU mock, OpenAI-compatible, exporting the same metric names as
  vLLM. Swap `workloads/vllm/` in on real hardware.
- **Karpenter:** not exercised on kind; documented in `terraform/`, not faked.
- **NetworkPolicy:** declared, not enforced (kindnet ignores it).
- **GPU utilisation:** not measured.

## What I would do differently at 10x

1. One ClusterQueue per cluster plus a global admission tier.
2. Chargeback by billing identity, not namespace.
3. Reconcile allocation estimates against the real monthly invoice.
