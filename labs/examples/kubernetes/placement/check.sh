#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo 'Use the Lab cluster'; exit 1;; esac
ns=lab-placement
kubectl -n "$ns" wait --for=condition=PodScheduled=false pod/placed --timeout=30s
kubectl -n "$ns" get events --field-selector reason=FailedScheduling
node=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("worker")) | .metadata.name')
kubectl label node "$node" lab-zone=nowhere --overwrite
kubectl -n "$ns" wait --for=condition=Ready pod/placed --timeout=90s
[ "$(kubectl -n "$ns" get pod placed -o jsonpath='{.spec.nodeName}')" = "$node" ]
kubectl label node "$node" lab-zone-
echo 'Selector filtered nodes; an eligible node allowed scheduling.'
