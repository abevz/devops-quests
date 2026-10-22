#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-probes
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
python3 prepare.py
kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
k apply -f lab-1.yaml
k wait --for=condition=Ready pod/probes --timeout=90s
