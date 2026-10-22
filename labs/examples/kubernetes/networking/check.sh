#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo 'Use the Lab cluster'; exit 1;; esac
ns=lab-networking
kubectl -n "$ns" wait --for=condition=Ready pod/web --timeout=90s
[ "$(kubectl -n "$ns" get endpointslice -l kubernetes.io/service-name=web -o json | jq '[.items[].endpoints[]?] | length')" = 0 ]
kubectl -n "$ns" patch service web --type merge -p '{"spec":{"selector":{"app":"web"}}}'
for try in $(seq 1 30); do
 # The Pod hostname is also "web" in /etc/hosts; the FQDN selects Service DNS.
 if kubectl -n "$ns" exec web -- wget -qO- -T 2 "http://web.$ns.svc.cluster.local" | grep -qx lab-network; then
   kubectl -n "$ns" get endpointslice -l kubernetes.io/service-name=web; exit 0
 fi
 sleep 1
done
exit 1
