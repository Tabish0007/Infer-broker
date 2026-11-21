# Architecture

```mermaid
flowchart TB
  subgraph teams["Teams"]
    A["team-a<br/>LocalQueue"]:::t
    B["team-b<br/>LocalQueue"]:::t
  end

  subgraph cp["Control plane"]
    K["Kueue<br/>ClusterQueue: shared-gpu-pool<br/>cohort + preemption"]
    ARGO["Argo CD<br/>app-of-apps"]
    CLI["platform CLI<br/>golden path"]
  end

  subgraph sched["Scheduling"]
    SCH["kube-scheduler<br/>real accounting"]
    N1["kind worker<br/>nvidia.com/gpu: 4 (simulated)"]
    N2["kind worker<br/>nvidia.com/gpu: 4 (simulated)"]
  end

  subgraph run["Workloads"]
    INF["mock-inference<br/>OpenAI-compatible"]
    JOB["batch Jobs<br/>GPU-requesting"]
  end

  subgraph obs["Observability + cost"]
    P["Prometheus"]
    G["Grafana<br/>€/1M tokens"]
    OC["OpenCost<br/>node + GPU pricing"]
    INV["chargeback.py<br/>weekly invoice"]
  end

  A --> K
  B --> K
  CLI --> A
  ARGO --> A
  K --> SCH
  SCH --> N1
  SCH --> N2
  N1 --> INF
  N2 --> JOB
  INF --> P
  JOB --> P
  OC --> G
  P --> G
  P --> INV

  classDef t fill:#e8f0fe,stroke:#4285f4
```

## Request path

1. A team submits a `Job` labelled `kueue.x-k8s.io/queue-name=default`.
2. Kueue admits it only if it fits the team's nominal quota (or can borrow from
   the cohort without starving another team), and creates a `Workload`.
3. The kube-scheduler places pods against **simulated but real-accounted**
   `nvidia.com/gpu` capacity.
4. The inference server emits `vllm:*` metrics; OpenCost emits node and GPU
   cost; Grafana joins them per team.
5. `chargeback.py` converts the same metrics into an invoice.

## Why the split between Kueue and ResourceQuota

They are not alternatives — they answer different questions.

| | `ResourceQuota` | Kueue `ClusterQueue` |
|---|---|---|
| Enforces | ceiling per namespace | fair-share policy across a shared pool |
| On breach | reject at admission, forever | queue, then admit when capacity frees |
| Borrowing | impossible | `cohort` + `borrowingLimit` |
| Preemption | none | priority-based eviction |
| Answers | "may you?" | "when?" |

Using only ResourceQuota gives you a platform where teams hoard quotas they
barely use and everyone runs at 15% utilisation. See `adr/0001`.
