set -euo pipefail
cd ~/quest
failed=0
if ! (
kubectl rollout status deployment/clock --timeout=3s
); then failed=1; fi
if ! (
pod=$(kubectl get pods -l app=clock -o jsonpath='{.items[0].metadata.name}') || exit $?
test "$(kubectl exec "$pod" -- cat /tmp/identity)" = "$pod"
); then failed=1; fi
if ! (
pod=$(kubectl get pods -l app=clock -o jsonpath='{.items[0].metadata.name}') || exit $?
kubectl exec "$pod" -- cat /tmp/clock | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
); then failed=1; fi
exit "$failed"
