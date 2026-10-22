#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-troubleshooting
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
k wait --for=jsonpath='{.status.containerStatuses[0].state.waiting.reason}'=ImagePullBackOff pod/missing-image --timeout=90s
k wait --for=jsonpath='{.status.containerStatuses[0].state.terminated.reason}'=OOMKilled pod/memory-limit --timeout=90s
[ "$(k get pod memory-limit -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}')" = 137 ]
k describe pod missing-image > image-pull.log
grep -q 'Failed to pull image' image-pull.log
# A shell-less application fails exec; the tools container sees its PID and root.
if k exec vg-k8s-app -c app -- sh > no-shell.log 2>&1; then echo 'Expected missing shell'; exit 1; fi
grep -Eq 'not found|no such file' no-shell.log
k exec vg-k8s-app -c tools -- sh -c 'test ! -f /root-marker; test "$(cat /proc/1/root/root-marker)" = scratch-root; test "$(cat /proc/1/root/data/marker)" = original'
k debug vg-k8s-app --image="$TOOLS" --image-pull-policy=Never --target=app --container=baseline --profile=baseline -- sh -c 'timeout 3 strace -f -p 1 -e trace=openat'
baseline_exit=
for try in $(seq 1 30); do
 baseline_exit=$(k get pod vg-k8s-app -o json | jq -r '.status.ephemeralContainerStatuses[]? | select(.name=="baseline") | .state.terminated.exitCode // empty')
 test -n "$baseline_exit" && break
 sleep 1
done
k logs vg-k8s-app -c baseline > baseline.log 2>&1
# Same-UID tracing can already work with classic Yama permissions. Bound that
# observation too, so its tracer detaches before the general-profile test.
case "$baseline_exit" in
 1) grep -Eq 'Operation not permitted|Permission denied' baseline.log ;;
 124|143) grep -Eq 'Process [0-9]+ attached' baseline.log ;;
 *) echo "Unexpected baseline tracing exit: $baseline_exit"; exit 1 ;;
esac
# The general profile grants ptrace; timeout only bounds observation.
set +e
k exec vg-k8s-app -c tools -- timeout 3 strace -f -p 1 -e trace=openat > trace.log 2>&1
trace_exit=$?
set -e
[ "$trace_exit" = 124 ] || [ "$trace_exit" = 143 ]
grep -q '/config/app.yaml' trace.log
k exec vg-k8s-app -c tools -- sh -c 'ss -ltn; dig +short vg-k8s-ok; curl -fsS --max-time 3 http://vg-k8s-ok' > network.log
grep -qx ok network.log
set +e
k exec vg-k8s-app -c tools -- curl -sS --max-time 3 http://vg-k8s-wrong > refused.log 2>&1
refused=$?
k exec vg-k8s-app -c tools -- curl -sS --max-time 3 http://127.0.0.1:8082 > reset.log 2>&1
reset=$?
set -e
[ "$refused" = 7 ]
[ "$reset" = 56 ]
k get endpointslices -l kubernetes.io/service-name=vg-k8s-empty -o json > empty-endpoints.json
python3 - <<'EMPTY'
import json
assert not any(e.get('conditions',{}).get('ready') for s in json.load(open('empty-endpoints.json'))['items'] for e in s.get('endpoints',[]))
EMPTY
# Packet capture uses the explicitly privileged network-debug profile.
k debug vg-k8s-app --image="$TOOLS" --image-pull-policy=Never --target=app --container=network-tools --profile=netadmin -- sleep 3600
for try in $(seq 1 40); do
 k exec vg-k8s-app -c network-tools -- true 2>/dev/null && break
 sleep 1
done
k exec vg-k8s-app -c network-tools -- sh -c 'timeout 5 tcpdump -ni any -c 1 "tcp[tcpflags] & tcp-rst != 0" > /tmp/reset.packets 2>&1 & capture=$!; sleep 1; curl -sS --max-time 2 http://127.0.0.1:8082 >/dev/null 2>&1 || true; wait "$capture"; cat /tmp/reset.packets' > packets.log
grep -q 'Flags \[R' packets.log
# A different backend Pod is essential for an egress-policy experiment.
k exec vg-k8s-app -c tools -- curl -fsS --max-time 3 http://policy-target > policy-before.log
k apply -f lab-19.yaml
blocked=0
for try in $(seq 1 20); do
 set +e
 k exec vg-k8s-app -c tools -- curl -sS --connect-timeout 2 --max-time 3 http://policy-target > policy-after.log 2>&1
 code=$?
 set -e
 if [ "$code" = 28 ]; then blocked=1; break; fi
 sleep 1
done
[ "$blocked" = 1 ] || { echo 'NetworkPolicy was not enforced'; exit 1; }
k exec vg-k8s-app -c tools -- dig +short "policy-target.$ns.svc.cluster.local" | grep -E '^[0-9]+\.'
k delete networkpolicy vg-k8s-deny
# Copying a crash Pod does not add tools to its shell-less image.
grep -q '/config/app.yaml' crash.log
jq -e '.status.containerStatuses[0].lastState.terminated.exitCode == 3' crash-status.json >/dev/null
k debug vg-k8s-crash --copy-to=lab-copy-fails --container=app -- sleep 3600
for try in $(seq 1 40); do
 k get pod lab-copy-fails -o json > copy-fails.json
 jq -e '.status.containerStatuses[]? | select(.state.waiting.reason=="RunContainerError" or .state.waiting.reason=="CreateContainerError")' copy-fails.json >/dev/null && break
 sleep 1
done
jq -e '.status.containerStatuses[]? | select(.state.waiting.reason=="RunContainerError" or .state.waiting.reason=="CreateContainerError")' copy-fails.json >/dev/null
k debug vg-k8s-crash --copy-to=lab-copy-fixed --container=app --set-image="app=$TOOLS" --image-pull-policy=Never --share-processes -- sleep 3600
k wait --for=condition=Ready pod/lab-copy-fixed --timeout=90s
# A copied Pod gets a new emptyDir; it is not a filesystem snapshot.
k exec vg-k8s-app -c tools -- sh -c 'echo changed > /proc/1/root/data/marker'
k debug vg-k8s-app --copy-to=lab-copy --container=copy-tools --image="$TOOLS" --image-pull-policy=Never --share-processes -- sleep 3600
k wait --for=condition=Ready pod/lab-copy --timeout=90s
k exec lab-copy -c copy-tools -- sh -c 'pid=$(pgrep -f "^/app$" | head -1); test -n "$pid"; test "$(cat /proc/$pid/root/data/marker)" = original'
# Debugging a node remains within the owned kind node, never the app host.
node=$(k get pod vg-k8s-app -o jsonpath='{.spec.nodeName}')
k debug "node/$node" --image="$TOOLS" --image-pull-policy=Never --profile=sysadmin -- sleep 3600
nodepod=$(k get pods -o json | jq -r '.items[] | select(.metadata.name|startswith("node-debugger-")) | .metadata.name' | head -1)
k wait --for=condition=Ready "pod/$nodepod" --timeout=90s
k exec "$nodepod" -- chroot /host crictl ps -o json > containers.json
cid=$(jq -r --arg ns "$ns" '.containers[] | select(.labels["io.kubernetes.pod.namespace"]==$ns and .labels["io.kubernetes.pod.name"]=="vg-k8s-app" and .metadata.name=="app") | .id' containers.json | head -1)
test -n "$cid"
k exec "$nodepod" -- chroot /host crictl inspect "$cid" > inspected.json
pid=$(jq -r '.info.pid' inspected.json)
k exec "$nodepod" -- nsenter -t "$pid" -n ss -ltn | grep ':8080'
k exec "$nodepod" -- cat "/proc/$pid/root/root-marker" | grep -qx scratch-root
k exec "$nodepod" -- chroot /host crictl logs --tail=2 "$cid" > cri.log
if k exec "$nodepod" -- nsenter -t "$pid" -m /bin/sh > mount-shell.log 2>&1; then echo 'Expected the scratch mount namespace to lack /bin/sh'; exit 1; fi
grep -Eq 'not found|No such file' mount-shell.log
k exec "$nodepod" -- nsenter -t "$pid" -p sh -c 'grep NSpid /proc/self/status' > namespace-pid.log
k exec "$nodepod" -- chroot /host journalctl -u kubelet -n 3 --no-pager > kubelet.log
echo 'Ephemeral containers, ptrace permissions, TCP failures, policy enforcement, Pod copies and node CRI inspection passed.'
