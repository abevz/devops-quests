#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-placement
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
python3 prepare.py
kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
kubectl taint node "$worker" dedicated=reserved:NoSchedule --overwrite
k apply -f lab-4.yaml -f lab-7.yaml
k wait --for=condition=Ready pod/placed --timeout=90s
kubectl taint node "$worker" dedicated:NoSchedule-
k apply -f lab-8.yaml -f lab-9.yaml
