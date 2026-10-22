#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-resources
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
[ "$(k get pod besteffort -o jsonpath='{.status.qosClass}')" = BestEffort ]
[ "$(k get pod burner -o jsonpath='{.status.qosClass}')" = Burstable ]
for try in $(seq 1 30); do
 throttled=$(k exec burner -- awk '/nr_throttled/{print $2}' /sys/fs/cgroup/cpu.stat)
 test "$throttled" -gt 0 && break
 sleep 1
done
test "$throttled" -gt 0
uid=$(k get pod resize -o jsonpath='{.metadata.uid}')
k patch pod resize --subresource=resize --patch-file source-7.json
for try in $(seq 1 40); do
 limits=$(k exec resize -- cat /sys/fs/cgroup/cpu.max)
 test "$limits" = '30000 100000' && break
 sleep 1
done
[ "$limits" = '30000 100000' ]
[ "$(k get pod resize -o jsonpath='{.metadata.uid}')" = "$uid" ]
[ "$(k get pod resize -o jsonpath='{.status.containerStatuses[0].restartCount}')" = 0 ]
echo 'QoS, CPU throttling and in-place CPU resize verified.'
