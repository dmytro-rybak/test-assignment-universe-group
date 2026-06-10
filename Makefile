CLUSTER_NAME ?= universe-group

.PHONY: help start wait-ready cluster-up cluster-down cluster-delete bootstrap forward argocd-password grafana-password

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

start: bootstrap wait-ready forward ## Bootstrap cluster and open port-forwards (single entry point)

wait-ready: ## Wait for Grafana to be ready after Argo CD sync
	@echo "Waiting for Grafana (Argo CD is syncing — may take a few minutes)..."
	@until kubectl get deployment grafana -n monitoring 2>/dev/null | grep -q grafana; do printf '.'; sleep 10; done && echo
	kubectl wait --for=condition=available deployment/grafana -n monitoring --timeout=300s

cluster-up: ## Start minikube cluster
	minikube start --profile=$(CLUSTER_NAME) --driver=docker \
		--container-runtime=containerd

cluster-down: ## Stop cluster (preserves state)
	minikube stop --profile=$(CLUSTER_NAME)

cluster-delete: ## Delete cluster entirely
	minikube delete --profile=$(CLUSTER_NAME)

bootstrap: cluster-up ## Install Argo CD and apply app-of-apps
	helm repo add argo https://argoproj.github.io/argo-helm --force-update
	helm upgrade --install argocd argo/argo-cd \
		--version 9.5.20 \
		--namespace argocd \
		--create-namespace \
		--set dex.enabled=false \
		--set notifications.enabled=false \
		--wait
	kubectl apply -f kubernetes/app-of-apps.yaml

forward: ## Port-forward Grafana → localhost:3001 and Argo CD → localhost:8081 (Ctrl-C to stop)
	@echo "Grafana:  http://localhost:3001"
	@echo "Argo CD:   http://localhost:8081"
	kubectl port-forward -n monitoring svc/grafana 3001:80 & \
	kubectl port-forward -n argocd svc/argocd-server 8081:80 & \
	wait

argocd-password: ## Print Argo CD admin credentials
	@echo "user: admin"
	@printf "password: "
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo

grafana-password: ## Print Grafana admin credentials
	@printf "user: "
	@kubectl -n monitoring get secret grafana \
		-o jsonpath="{.data.admin-user}" | base64 -d && echo
	@printf "password: "
	@kubectl -n monitoring get secret grafana \
		-o jsonpath="{.data.admin-password}" | base64 -d && echo
