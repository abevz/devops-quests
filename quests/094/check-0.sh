set -euo pipefail
cd ~/quest
test "$(cat /run/dq/facts/0/initial-throttled)" -ge 10
kubectl get deployment board -o json | jq -e --arg command 'mkdir -p /tmp/site; printf "%s\n" "north-94" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site' '.spec.replicas==1 and .spec.template.spec.containers[0].resources=={requests:{cpu:"50m",memory:"8Mi"},limits:{cpu:"50m",memory:"32Mi"}} and .spec.template.spec.containers[0].command==["sh","-c",$command] and .status.readyReplicas==1' >/dev/null
sample=$(bash measure.sh)
if test "$sample" -gt 5; then printf "Idle sample still throttled: %s\n" "$sample" >&2; exit 1; fi
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-94
