set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
kubectl rollout status deployment/stable --timeout=3s
)
[ $? -eq 0 ] || failed=1
(
set -e
bad=$(kubectl get pods -l app=quarantine -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null and .status.phase=="Running")]|if length==1 then .[0].metadata.name else error("expected one current Running quarantine Pod") end')
)
[ $? -eq 0 ] || failed=1
(
set -e
bad=$(kubectl get pods -l app=quarantine -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null and .status.phase=="Running")]|if length==1 then .[0].metadata.name else error("expected one current Running quarantine Pod") end') || exit $?
kubectl get pod "$bad" -o json | jq -e '.status.phase=="Running" and any(.status.conditions[]; .type=="Ready" and .status=="False")' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
bad=$(kubectl get pods -l app=quarantine -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null and .status.phase=="Running")]|if length==1 then .[0].metadata.name else error("expected one current Running quarantine Pod") end') || exit $?
test "$(kubectl exec "$bad" -c worker -- printenv ROUTE)" = retired
)
[ $? -eq 0 ] || failed=1
(
set -e
good=$(kubectl get pods -l app=stable -o jsonpath='{.items[0].metadata.name}') || exit $?
test "$(kubectl get endpointslices -l kubernetes.io/service-name=departures -o json | jq -r '[.items[].endpoints[] | select(.conditions.ready==true) | .targetRef.name] | unique | .[]')" = "$good"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
