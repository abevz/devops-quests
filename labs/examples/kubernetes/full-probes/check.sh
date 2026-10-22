#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-probes
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
k exec probes -- rm /usr/share/nginx/html/index.html
k wait --for=condition=Ready=false pod/probes --timeout=30s
for try in $(seq 1 45); do
 count=$(k get pod probes -o jsonpath='{.status.containerStatuses[0].restartCount}')
 if [ "$count" -gt 0 ]; then k wait --for=condition=Ready pod/probes --timeout=90s; echo 'HTTP probe failure caused a restart and readiness recovered.'; exit 0; fi
 sleep 1
done
exit 1
