# Production path — NOT deployed by this repo

The demo runs on kind with simulated GPU capacity. This directory documents what
the real thing looks like, so the reasoning is reviewable without spending money.

```
terraform/
├── eks.tf          # EKS cluster, OIDC, core addons
├── karpenter.tf    # NodePools: spot-first GPU + consolidation
├── kueue.tf        # Kueue install, ResourceFlavors mapped to real instance types
└── variables.tf
```

## Ordering constraint worth knowing
Kueue admits against `nominalQuota`, Karpenter then provisions nodes to satisfy
it. If `nominalQuota` is set *below* what Karpenter can provide, you leave
capacity on the table. If it is set *above*, workloads get admitted and then sit
unschedulable, which looks exactly like a Kueue bug and is not one. Set
`nominalQuota` to the NodePool ceiling.

## NodePool sketch

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata: { name: gpu-spot }
spec:
  disruption: { consolidationPolicy: WhenEmptyOrUnderutilized, consolidateAfter: 60s }
  limits: { nvidia.com/gpu: "32" }
  template:
    spec:
      requirements:
        - { key: karpenter.sh/capacity-type, operator: In, values: ["spot"] }
        - { key: node.kubernetes.io/instance-type, operator: In, values: ["g5.xlarge", "g6.xlarge"] }
      nodeClassRef: { name: default }
      taints:
        - { key: nvidia.com/gpu, value: "true", effect: NoSchedule }
```
