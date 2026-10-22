set -euo pipefail
cd ~/quest
helm get values board -o json | jq -e '.readinessPort==8080' >/dev/null
helm history board -o json | jq -e 'length>=3 and .[-1].status=="deployed"' >/dev/null
test "$(kubectl get deployment board -o jsonpath='{.metadata.uid}')" = "$(cat /run/dq/facts/0/original-deployment-uid)"
kubectl get deployment board -o json | jq -e '.spec.template.spec.containers[0].readinessProbe.httpGet.port==8080' >/dev/null
kubectl rollout status deployment/board --timeout=3s >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://127.0.0.1:8080)" = north-67
