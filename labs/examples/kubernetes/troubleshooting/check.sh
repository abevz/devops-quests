#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo 'Use the Lab cluster'; exit 1;; esac
ns=lab-troubleshooting
for try in $(seq 1 40); do
 code=$(kubectl -n "$ns" get pod crash -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}')
 reason=$(kubectl -n "$ns" get pod missing -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}')
 # The status can appear before the previous container log is readable.
 if [ "$code" = 3 ] && [ "$reason" = ErrImageNeverPull ] && kubectl -n "$ns" logs crash --previous | grep configuration-missing; then
   kubectl -n "$ns" get events --field-selector involvedObject.name=missing
   echo 'The process failure and image availability failure are separate layers.'; exit 0
 fi
 sleep 2
done
kubectl -n "$ns" get pod crash,missing -o yaml
exit 1
