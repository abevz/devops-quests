set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set +e
(
set -e
kubectl rollout status deployment/reader --timeout=3s
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The reader rollout is incomplete: ✗ [DQ:reader_rollout]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
pod=$(kubectl get pods -l app=reader -o jsonpath='{.items[0].metadata.name}')
test "$(kubectl exec "$pod" -c worker -- cat /tmp/route)" = north
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The reader route file could not be verified: ✗ [DQ:reader_route]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
kubectl get deployment reader -o json | jq -e '.spec.template.spec.containers as $containers | [$containers[]? | select(.name=="worker")] as $workers | ($workers|length)==1 and ([$workers[0].env[]? | select(.name=="ROUTE")] as $routes | ($routes|length)>0 and all($routes[]; .value==null or .value=="") and ($routes[-1].valueFrom|keys)==["secretKeyRef"] and $routes[-1].valueFrom.secretKeyRef.name=="station" and $routes[-1].valueFrom.secretKeyRef.key=="route")' >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The worker ROUTE reference does not match the Secret contract: ✗ [DQ:secret_reference]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
