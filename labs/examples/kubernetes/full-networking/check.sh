#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-networking
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
[ "$(k get pods -l app=lonely -o json | jq '.items|length')" = 0 ]
[ "$(k get endpointslice -l kubernetes.io/service-name=web -o json | jq '[.items[].endpoints[]?]|length')" = 0 ]
k apply -f lab-8.yaml
for try in $(seq 1 30); do
 count=$(k get endpointslice -l kubernetes.io/service-name=web -o json | jq '[.items[].endpoints[]? | select(.conditions.ready)]|length')
 test "$count" = 2 && break
 sleep 1
done
[ "$count" = 2 ]
k exec deployment/web -- wget -qO- -T 3 http://web | grep -q 'Welcome to nginx'
echo 'Selectors, ready EndpointSlices and actual HTTP traffic verified.'
