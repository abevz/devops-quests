#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo 'Use the Lab cluster'; exit 1;; esac
ns=lab-configuration
kubectl -n "$ns" wait --for=condition=Ready pod/reader --timeout=90s
kubectl -n "$ns" patch configmap settings --type merge -p '{"data":{"message":"second"}}'
[ "$(kubectl -n "$ns" exec reader -- printenv MESSAGE)" = first ]
for try in $(seq 1 100); do
 if [ "$(kubectl -n "$ns" exec reader -- cat /settings/message)" = second ]; then echo 'Volume updated; existing process environment stayed first.'; exit 0; fi
 sleep 2
done
exit 1
