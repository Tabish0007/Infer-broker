# ADR 0005 — Deliberately not using a service mesh

**Status:** accepted · **Date:** 2026-11

## Context
A GPU inference platform "should" have mTLS, retries, traffic splitting, and
per-route metrics. A service mesh (Istio/Linkerd) provides all of it.

## Decision
Not now. The platform has three services and one ingress path. A mesh would add
two control-plane components, a sidecar per pod (or an ambient data path), a new
CRD surface to debug, and a new failure mode where a control-plane hiccup breaks
data-plane routing — in exchange for capabilities that are not yet the bottleneck.

What actually mattered here was *cost attribution and admission control*, and a
mesh provides neither.

## What we do instead
- Scope: `NetworkPolicy` for isolation, documented as unenforced on kindnet.
- Retries: client-side, with idempotency keys.
- Traffic splitting: Argo Rollouts when canary deploys become necessary.
- mTLS: revisit when there is a real cross-namespace or cross-cluster call.

## Consequences
- **Positive:** fewer moving parts; the debugging surface stays small.
- **Negative:** no per-route golden signals; latency attribution stops at the
  service boundary.
- **Revisit trigger, written down now:** more than 10 services, or a compliance
  requirement for mTLS in transit, or a need for per-tenant rate limiting at the
  network layer. Until one of those is true, this stays rejected.

## Why this ADR exists at all
Saying no, in writing, with a trigger for revisiting, is the part of platform
engineering that does not show up in a `kubectl apply` diff.
