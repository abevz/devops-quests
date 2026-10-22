#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-disruption
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
python3 prepare.py
kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
k create deployment web --image="$NGINX" --replicas=2
k rollout status deployment/web --timeout=90s
k apply -f lab-1.yaml
k wait --for=jsonpath='{.status.currentHealthy}'=2 pdb/web --timeout=40s
