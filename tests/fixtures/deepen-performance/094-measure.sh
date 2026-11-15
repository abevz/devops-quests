#!/bin/bash
set -euo pipefail
cd ~/quest
pod=$(kubectl get pods -l app=board -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null)][0].metadata.name')
# Read within one exec: launching a separate reader spends this container's CPU quota.
kubectl exec "$pod" -- sh -c '
read_counter() {
 while read -r key value rest; do
  if test "$key" = nr_throttled; then printf "%s\n" "$value"; return; fi
 done < /sys/fs/cgroup/cpu.stat
 return 1
}
before=$(read_counter)
sleep 2
after=$(read_counter)
printf "%s\n" "$((after-before))"
'
