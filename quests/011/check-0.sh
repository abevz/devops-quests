set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
kubectl rollout status deployment/clock --timeout=3s
)
[ $? -eq 0 ] || failed=1
(
set -e
pod=$(kubectl get pods -l app=clock -o jsonpath='{.items[0].metadata.name}') || exit $?
test "$(kubectl exec "$pod" -- cat /tmp/identity)" = "$pod"
)
[ $? -eq 0 ] || failed=1
(
set -e
pod=$(kubectl get pods -l app=clock -o jsonpath='{.items[0].metadata.name}') || exit $?
kubectl exec "$pod" -- cat /tmp/clock | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
)
[ $? -eq 0 ] || failed=1
exit "$failed"
