#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo 'Use the Lab cluster'; exit 1;; esac
kubectl -n lab-resources wait --for=condition=PodScheduled=false pod/oversized --timeout=30s
kubectl -n lab-resources wait --for=condition=Ready pod/bounded --timeout=90s
[ "$(kubectl -n lab-resources get pod bounded -o jsonpath='{.status.qosClass}')" = Burstable ]
kubectl -n lab-resources get events --field-selector reason=FailedScheduling
kubectl -n lab-resources exec bounded -- sh -c 'cat /sys/fs/cgroup/cpu.max; cat /sys/fs/cgroup/memory.max'
echo 'Requests govern placement; cgroup files show runtime limits.'
