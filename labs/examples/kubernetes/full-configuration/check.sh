#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-configuration
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
k apply -f lab-4.yaml
for try in $(seq 1 90); do
 value=$(k exec config-reader -- cat /config/mode)
 test "$value" = green && break
 sleep 2
done
[ "$value" = green ]
[ "$(k exec config-reader -- printenv MODE)" = blue ]
[ "$(k exec config-reader -- cat /single)" = blue ]
[ "$(k exec projected -- cat /input/pod-name)" = projected ]
k exec projected -- test -s /input/token
echo 'Directory projection updated; env and subPath stayed blue. Downward API and a projected token exist.'
