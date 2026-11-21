CLUSTER   ?= gpu-platform
TEAM      ?= team-a
WINDOW    ?= 15m
IMAGE     ?= mock-inference:dev
NAMESPACE ?= team-a

.PHONY: help up cluster check-kueue-api fake-gpu build load tenancy kueue \
        workload observability deploy invoice demo-quota scale-zero down clean

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

up: cluster fake-gpu build load kueue tenancy observability workload deploy ## Full demo environment
	@echo ""
	@echo "  Grafana:  make grafana"
	@echo "  Endpoint: make port-forward"
	@echo "  Quotas:   make demo-quota"

cluster: ## Create the kind cluster
	kind get clusters | grep -qx $(CLUSTER) || kind create cluster --name $(CLUSTER) --config kind/cluster.yaml

check-kueue-api: ## Show which Kueue API versions this cluster serves
	@kubectl api-resources --api-group=kueue.x-k8s.io 2>/dev/null || echo "kueue CRDs not installed yet"

fake-gpu: ## Advertise fake nvidia.com/gpu capacity on kind workers
	./scripts/fake-gpu.sh

build: ## Build the mock inference image
	docker build -t $(IMAGE) workloads/mock-inference

load: ## Load the image into kind
	kind load docker-image $(IMAGE) --name $(CLUSTER)

kueue: ## Install Kueue and apply the queue topology
	kubectl apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/v0.11.1/manifests.yaml
	kubectl -n kueue-system rollout status deploy/kueue-controller-manager --timeout=300s
	kubectl apply -f platform/kueue/namespaces.yaml
	kubectl apply -f platform/kueue/resourceflavors.yaml
	kubectl apply -f platform/kueue/clusterqueue.yaml
	sleep 3
	kubectl apply -f platform/kueue/team-queues.yaml

tenancy: ## Create the demo teams
	TEAM=$(TEAM) ./cli/platform new-team $(TEAM) 4
	./cli/platform new-team team-b 4

observability: ## Prometheus + Grafana + OpenCost
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
	helm repo add opencost https://opencost.github.io/opencost-helm-chart >/dev/null
	helm repo update >/dev/null
	helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
	  -n monitoring --create-namespace --wait --timeout 10m \
	  -f platform/observability/prometheus-values.yaml
	helm upgrade --install opencost opencost/opencost -n opencost --create-namespace \
	  -f platform/observability/opencost-values.yaml

workload: ## Deploy the inference API into the demo namespace
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	sed -e "s|__IMAGE__|$(IMAGE)|g" -e "s|__TEAM__|$(TEAM)|g" \
	  workloads/mock-inference/deployment.yaml | kubectl apply -n $(NAMESPACE) -f -

deploy: workload ## Alias

port-forward: ## Expose the inference API on localhost:8080
	kubectl -n $(NAMESPACE) port-forward svc/mock-inference 8080:80

grafana: ## Open Grafana (admin / prom-operator)
	kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

invoice: ## Per-team cost invoice
	./scripts/invoice.sh $(TEAM) $(WINDOW)

demo-quota: ## Admit / reject / preempt demonstration
	./scripts/demo-quota.sh

scale-zero: ## Watch the deployment scale to zero
	kubectl -n $(NAMESPACE) get deploy mock-inference -w

down: ## Delete the cluster
	kind delete cluster --name $(CLUSTER)

clean: down ## Full teardown
