# ADR 0002 — Karpenter over static node pools (production path)

**Status:** accepted, not exercised in the demo · **Date:** 2026-11

## Context
GPU nodes are the most expensive line item in the cluster and are idle most of
the time. Static node pools mean paying for capacity through the troughs.

## Decision
The production path uses Karpenter `NodePool`s with spot-first capacity and
consolidation enabled. Kueue's `nominalQuota` is set to the *maximum* the
autoscaler can provide, because Kueue admits against quota and Karpenter then
fulfils it — the two must agree or you get admitted-but-unschedulable workloads.

## Consequences
- **Positive:** GPU spend tracks demand; spot + consolidation is the single
  largest cost lever available.
- **Negative:** cold start moves from "zero" to "node provision + image pull +
  model load", which can be minutes. Anything interactive needs a warm floor.

## Why it is not in the demo
Karpenter provisions cloud nodes through a cloud provider API. On `kind` there
is nothing for it to provision, so exercising it would mean faking an AWS API —
effort with no signal. `terraform/` documents the module instead, and the demo
fakes capacity by patching node status, which is honest about what is real.

## What I'd revisit at 10×
Consolidation evicts pods; with long-running inference that becomes disruptive.
Needs `do-not-disrupt` annotations and a warm pool sized to p95 concurrency.
