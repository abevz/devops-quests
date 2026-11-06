set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
test "$(cat /run/dq/facts/0/initial-throttled)" -ge 10
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get deployment board -o json | jq -e '.spec.replicas==1' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get deployment board -o json | jq -e '.spec.template.spec.containers[0].resources=={requests:{cpu:"50m",memory:"8Mi"},limits:{cpu:"50m",memory:"32Mi"}}' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get deployment board -o json | jq -e --arg command 'mkdir -p /tmp/site; printf "%s\n" "north-94" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site' '.spec.template.spec.containers[0].command==["sh","-c",$command]' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get deployment board -o json | jq -e '.status.readyReplicas==1' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
sample=$(bash measure.sh)
if test "$sample" -gt 5; then printf "Idle sample still throttled: %s\n" "$sample" >&2; exit 1; fi
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-94
)
[ $? -eq 0 ] || failed=1
exit "$failed"
