# ADR 0004 — Chargeback by GPU-hours, not by even split

**Status:** accepted · **Date:** 2026-11

## Context
The platform needs to answer "what does Team A cost us?" in a way Team A will
accept. Three candidate models:

1. **Even split of the cluster bill.** Simple, universally resented, and it
   removes any incentive to be efficient. Rejected.
2. **Requested resources × duration.** Transparent, auditable from Kubernetes,
   and it charges for what was *reserved* rather than what was *used*. Teams
   that reserve and idle pay full price — which is the behaviour we want to
   discourage, so we keep it.
3. **Measured utilisation (DCGM/GPU-time).** Most accurate, needs the GPU
   operator and per-device telemetry, and is unexplainable to a finance team.

## Decision
Model 2, with pricing as an explicit, versioned input rather than a derived
number:

    cost(team) = gpu_hours × €/gpu_hour + cpu_core_hours × €/core_hour
    cost_per_1M_tokens = cost / (generated_tokens / 1e6)

No hidden multiplier, no "platform overhead" line. The rates live in
`cli/chargeback.py` where they can be argued with.

## Consequences
- **Honest:** the invoice is reproducible from Prometheus by anyone with access.
- **Known bias:** a team that over-reserves is over-charged relative to true
  consumption. This is deliberate and documented, not an oversight.
- **Known gap:** shared nodes mean a core-hour is not the same as a dedicated
  core-hour. The model overstates cost on shared nodes. At real scale this needs
  node-level allocation (OpenCost already computes it) rather than a flat rate.
- **Cost per 1M tokens is the headline metric**, because it is the only number
  that lets someone compare two models or two architectures.

## What I'd revisit at 10×
Move to OpenCost's node-level allocation, tag by billing identity rather than
namespace, and emit to a real billing system rather than a markdown invoice.
