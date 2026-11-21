# ADR 0003 — Scale-to-zero silently breaks streaming inference

**Status:** accepted with mitigations · **Date:** 2026-11

## Context
Scale-to-zero is the obvious cost win: idle replicas cost money for nothing. For
a streaming LLM endpoint it introduces a failure that does not appear in
dashboard averages.

## The failure
A request is streaming tokens. KEDA scales the deployment to zero because the
metric it watches (in-flight requests, or queue depth) reads as idle — it does
not understand a long-lived SSE connection. The pod is terminated mid-stream.
The client sees a truncated completion with no error. From the platform's
metrics, it looks like a successful request with a short response.

This is worse than a hard failure: it corrupts output silently.

## Decision
Two tiers instead of one policy.

| Tier | Models | Policy |
|---|---|---|
| interactive | user-facing chat | `minReplicas: 1`, never scale to zero, `terminationGracePeriodSeconds: 120` |
| batch | async, evals, bulk | scale to zero freely; cold start is acceptable |

Plus: KEDA's scale-down stabilisation window is longer than the longest expected
stream, and "successful but truncated" is an explicit alert —
`(generated_tokens / expected_tokens) < 0.9` on streaming requests.

## Consequences
- Interactive tier gives up the idle-cost saving. That is the correct trade;
  correctness beats a 20% bill reduction.
- Cold start becomes a product decision with an SLA, not a platform accident.
- Anything scaled to zero needs a documented p95 cold start number. Ours is in
  `results/measurements.md`.

## What I'd revisit at 10×
Predictive pre-warming from traffic periodicity, instead of reactive scaling.
