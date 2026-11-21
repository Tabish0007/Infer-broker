# ADR 0006 — What is simulated, and why I am telling you

**Status:** accepted · **Date:** 2026-11

Judgement is mostly visible in what someone refuses to fake. Everything below is
labelled in the README, not buried here.

| Thing | Status | Why | What would change it |
|---|---|---|---|
| `nvidia.com/gpu` capacity | **Fake** — patched into `status.allocatable` on kind workers | No GPU hardware, no driver. The scheduler's accounting is real: pods are refused when the number runs out. | A single spot GPU instance, or a GPU dev box |
| Inference server | **CPU mock**, not vLLM | vLLM needs a GPU. The mock is OpenAI-compatible and emits identical metric names, so the platform layers are exercised for real. | Swap `workloads/vllm/deployment.yaml` |
| Karpenter | **Not exercised** | Nothing to provision on kind | EKS cluster |
| NetworkPolicy | **Declared, unenforced** | kindnet ignores it | Calico/Cilium CNI |
| GPU utilisation (DCGM) | **Not measured** | Requires the GPU operator | Real GPU nodes |
| Costs | **Explicit model**, not cloud billing | No cloud account attached | OpenCost cloud pricing |

A results table with one honest "not measured — would require a GPU" is worth
more than six plausible-looking fabricated numbers.
