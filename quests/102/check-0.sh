set -euo pipefail
cd ~/quest
test "$(kubectl get deployment board -o jsonpath='{.metadata.uid}')" = "$(cat /run/dq/facts/0/original-deployment-uid)"
kubectl get deployment board -o json | jq -e '.spec.replicas==2 and .spec.strategy.type=="RollingUpdate" and .spec.strategy.rollingUpdate=={maxSurge:1,maxUnavailable:0} and .status.readyReplicas==2 and .spec.template.spec.containers[0].readinessProbe.httpGet.port==8080' >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-102
