#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-storage
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
k exec stored -- sh -c 'echo retained > /data/extra-marker'
k delete pod stored --wait=true
k apply -f lab-1.yaml
k wait --for=condition=Ready pod/stored --timeout=90s
[ "$(k exec stored -- cat /data/extra-marker)" = retained ]
[ "$(k get pvc data -o jsonpath='{.status.phase}')" = Bound ]
echo 'Bound PVC data survived replacing its Pod.'
