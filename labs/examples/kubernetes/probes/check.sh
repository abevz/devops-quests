#!/bin/bash
set -euo pipefail
kubectl -n lab-probes exec probe -- touch /tmp/ready
kubectl -n lab-probes wait --for=condition=Ready pod/probe --timeout=30s
kubectl -n lab-probes exec probe -- rm /tmp/ready
kubectl -n lab-probes wait --for=condition=Ready=false pod/probe --timeout=30s
[ "$(kubectl -n lab-probes get pod probe -o jsonpath='{.status.containerStatuses[0].restartCount}')" = 0 ]
kubectl -n lab-probes exec probe -- rm /tmp/live
for attempt in $(seq 1 40); do
  count=$(kubectl -n lab-probes get pod probe -o jsonpath='{.status.containerStatuses[0].restartCount}')
  if [ "$count" -gt 0 ]; then printf 'readiness removed traffic eligibility; liveness restarted the container\n'; exit 0; fi
  sleep 1
done
exit 1
