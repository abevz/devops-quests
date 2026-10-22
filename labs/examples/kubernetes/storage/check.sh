#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo 'Use the Lab cluster'; exit 1;; esac
ns=lab-storage
kubectl -n "$ns" wait --for=condition=Ready pod/writer --timeout=90s
kubectl -n "$ns" exec writer -- sh -c 'echo preserved-volume > /data/marker'
kubectl -n "$ns" delete pod writer --wait=true
kubectl -n "$ns" apply -f objects.yaml
kubectl -n "$ns" wait --for=condition=Ready pod/writer --timeout=90s
[ "$(kubectl -n "$ns" exec writer -- cat /data/marker)" = preserved-volume ]
kubectl -n "$ns" get pvc,pod
echo 'A new Pod mounted the same persistent bytes.'
