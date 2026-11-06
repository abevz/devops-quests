set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
kubectl rollout status deployment/reader --timeout=3s
)
[ $? -eq 0 ] || failed=1
(
set -e
pod=$(kubectl get pods -l app=reader -o jsonpath='{.items[0].metadata.name}')
test "$(kubectl exec "$pod" -- cat /tmp/route)" = north
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get deployment reader -o json | jq -e '.spec.template.spec.containers[0].env[0].valueFrom.secretKeyRef=={"name":"station","key":"route"}' >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
