CLUSTER_NAME ?= universe-group

.PHONY: help cluster-up cluster-down cluster-delete bootstrap forward argocd-password

help:
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

cluster-up: ## Start minikube cluster
	minikube start --profile=$(CLUSTER_NAME) --driver=docker --extra-config=scheduler.bind-address=0.0.0.0 --extra-config=controller-manager.bind-address=0.0.0.0 --extra-config=etcd.listen-metrics-urls=http://0.0.0.0:2381

cluster-down: ## Stop minikube cluster (preserves state)
	minikube stop --profile=$(CLUSTER_NAME)

cluster-delete: ## Delete minikube cluster entirely
	minikube delete --profile=$(CLUSTER_NAME)

bootstrap: cluster-up ## Start cluster and install ArgoCD + app-of-apps
	helm repo add argo https://argoproj.github.io/argo-helm --force-update
	helm upgrade --install argocd argo/argo-cd \
		--version 9.5.20 \
		--namespace argocd \
		--create-namespace \
		--set dex.enabled=false \
		--set notifications.enabled=false \
		--wait
	kubectl apply -f kubernetes/app-of-apps.yaml

forward: ## Port-forward Grafana + ArgoCD to localhost (Ctrl-C to stop)
	@echo "Grafana:  http://localhost:3001"
	@echo "ArgoCD:   http://localhost:8081"
	kubectl port-forward -n monitoring svc/grafana 3001:80 & \
	kubectl port-forward -n argocd svc/argocd-server 8081:80 & \
	wait

argocd-password: ## Print the ArgoCD admin credentials
	@echo "user: admin"
	@printf "password: "
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo

grafana-password: ## Print the Grafana admin credentials
	@printf "user: "
	@kubectl -n monitoring get secret grafana \
		-o jsonpath="{.data.admin-user}" | base64 -d && echo
	@printf "password: "
	@kubectl -n monitoring get secret grafana \
		-o jsonpath="{.data.admin-password}" | base64 -d && echo
