set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
kubectl get deployment board -o json | jq -e ' .spec.replicas==1' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get deployment board -o json | jq -e '.spec.template.spec.containers[0].resources | .requests.cpu=="100m" and .limits.cpu=="300m"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get deployment board -o json | jq -e '.spec.template.spec.containers[0].resources | .requests.memory=="16Mi" and .limits.memory=="64Mi"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/board --timeout=3s
)
[ $? -eq 0 ] || failed=1
(
set -e
pod=$(kubectl get pods -l app=board -o jsonpath='{.items[0].metadata.name}')
test "$(kubectl exec "$pod" -- wget -qO- http://127.0.0.1:8080)" = north
)
[ $? -eq 0 ] || failed=1
exit "$failed"
