# Infer-broker

[![Python 3.10+](https://img.shields.io/badge/python-3.10+-blue.svg)](https://www.python.org/downloads/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Kubernetes](https://img.shields.io/badge/kubernetes-v1.28+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)

**Self-service GPU inference on Kubernetes with per-team chargeback.**

Companies buy GPUs. Teams hoard them. Finance gets a massive bill with zero attribution. This platform fixes that. Teams get a namespace, a quota, and a model endpoint in one command. Finance gets a cost-per-million-tokens number.

## The Problem

A company buys eight GPUs. One team reserves them and uses 15%. Another team's job is rejected while the pool sits idle. The bill arrives as one number, so everyone asks for more capacity and finance says no.

Quota alone cannot fix this: a quota is a ceiling, not a share. This replaces the ceiling with a queue, and adds attribution.

## What It Does

| Layer | Implementation | Why |
| :--- | :--- | :--- |
| **Tenancy** | `cli/platform new-team` -> namespace, ResourceQuota, LimitRange, NetworkPolicy, LocalQueue | Onboarding is self-service, not a ticket |
| **Admission** | Kueue ClusterQueue + cohorts + WorkloadPriorityClass | Shared pool without starvation |
| **Serving** | OpenAI-compatible endpoint, scale-to-zero on idle | Idle capacity costs nothing |
| **Chargeback** | Per-pod allocation -> GPU-hours -> EUR invoice | The part nobody has |

## Results (Executed on `kind`)

| Check | Result |
| :--- | :--- |
| Job requesting 2 GPUs | Admitted, pod Running |
| Job requesting 16 GPUs (quota = 4) | Refused at admission: `requests must not be above the limitRange max` |
| Invoice for team-a | **1.000 GPU-hours -> €1.00**, attributed to `team-a` |
| Live endpoint | Streaming SSE responses served |
| Environment check | 7 passed, 0 failed |
## Quickstart

```bash
make up            # kind + Kueue + observability + demo team
make demo-quota    # admission / refusal
make port-forward  # localhost:8080
make invoice TEAM=team-a
