# ADR 0001 — Kueue for GPU admission instead of plain ResourceQuota

**Status:** accepted · **Date:** 2026-11

## Context
Teams need to share a small, expensive GPU pool. The naive approach is one
`ResourceQuota` per namespace. It fails in a specific, expensive way: quota is a
ceiling, not a share. Team A requests 8 GPUs and uses 1; Team B's job is rejected
at admission even though 7 GPUs are idle. Utilisation collapses and everyone asks
for more quota than they need, which is rational behaviour under that policy.

## Decision
Admission control moves to Kueue. Each team gets a `LocalQueue`; all queues feed
a single `ClusterQueue` in a cohort. Teams get nominal quota, may borrow unused
capacity, and a low-priority batch job is preempted by an interactive one.

`ResourceQuota` stays as a hard ceiling — defence in depth, so a misconfigured
job cannot request a whole node's worth of GPU by accident.

## Consequences
- **Positive:** idle capacity gets used; no quota-hoarding incentive; priority is
  expressed in policy rather than in Slack messages.
- **Negative:** a new control plane (Kueue) to operate; pending jobs need
  monitoring or they silently sit in a queue; preemption means batch work is
  interruptible, which must be a documented property of the batch tier.

## What I'd revisit at 10×
One `ClusterQueue` becomes a scaling bottleneck past a few hundred concurrent
workloads. At that point: per-cluster queues plus a global admission tier.
