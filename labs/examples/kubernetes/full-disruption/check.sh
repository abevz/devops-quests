#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-disruption
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
pod=$(k get pod -l app=web -o jsonpath='{.items[0].metadata.name}')
node=$(k get pod "$pod" -o jsonpath='{.spec.nodeName}')
trap 'kubectl uncordon "$node"' EXIT
if kubectl drain "$node" --pod-selector=app=web --ignore-daemonsets --timeout=8s > drain.log 2>&1; then echo 'Expected blocked drain'; exit 1; fi
grep -q 'disruption budget' drain.log
[ "$(kubectl get node "$node" -o jsonpath='{.spec.unschedulable}')" = true ]
[ "$(k get pdb web -o jsonpath='{.status.disruptionsAllowed}')" = 0 ]
kubectl uncordon "$node"
trap - EXIT
echo 'Drain cordoned the node but the PDB prevented eviction.'
