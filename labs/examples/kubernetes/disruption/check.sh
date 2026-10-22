#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo 'Use the Lab cluster'; exit 1;; esac
ns=lab-disruption
kubectl -n "$ns" rollout status deployment/web --timeout=90s
kubectl -n "$ns" wait --for=jsonpath='{.status.currentHealthy}'=2 pdb/web --timeout=30s
pod=$(kubectl -n "$ns" get pod -l app=web -o jsonpath='{.items[0].metadata.name}')
printf '{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"%s","namespace":"%s"}}' "$pod" "$ns" > eviction.json
if kubectl create --raw "/api/v1/namespaces/$ns/pods/$pod/eviction" -f eviction.json > denied.log 2>&1; then echo 'Expected PDB denial'; exit 1; fi
grep -q 'disruption budget' denied.log
kubectl -n "$ns" patch pdb web --type merge -p '{"spec":{"minAvailable":1}}'
kubectl -n "$ns" wait --for=jsonpath='{.status.disruptionsAllowed}'=1 pdb/web --timeout=30s
kubectl create --raw "/api/v1/namespaces/$ns/pods/$pod/eviction" -f eviction.json
kubectl -n "$ns" rollout status deployment/web --timeout=90s
echo 'The eviction API respected the PDB.'
