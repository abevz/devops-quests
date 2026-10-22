#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-networking
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
kubectl delete namespace "$ns" --ignore-not-found --wait=true
