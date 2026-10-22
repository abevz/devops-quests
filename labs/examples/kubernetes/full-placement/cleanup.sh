#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-placement
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
kubectl taint node "$worker" dedicated:NoSchedule- 2>/dev/null || true
kubectl delete priorityclass vg-k8s-important --ignore-not-found
kubectl delete namespace "$ns" --ignore-not-found --wait=true
