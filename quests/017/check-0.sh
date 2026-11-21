set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
kubectl rollout status deployment/stable --timeout=3s || {
  code=$?
  printf '%s\n' 'Deployment stable rollout is complete: ✗ [DQ:condition_0]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
bad=$(kubectl get pods -l app=quarantine -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null and .status.phase=="Running")]|if length==1 then .[0].metadata.name else error("expected one current Running quarantine Pod") end') || {
  code=$?
  printf '%s\n' 'Exactly one current quarantine Pod is Running: ✗ [DQ:condition_1]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
if bash -euo pipefail <<'DQ_PREDICATE'
bad=$(kubectl get pods -l app=quarantine -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null and .status.phase=="Running")]|if length==1 then .[0].metadata.name else error("expected one current Running quarantine Pod") end') || exit $?
kubectl get pod "$bad" -o json | jq -e '.status.phase=="Running" and any(.status.conditions[]; .type=="Ready" and .status=="False")' >/dev/null
DQ_PREDICATE
then
  :
else
  code=$?
  printf '%s\n' 'The Running quarantine Pod has Ready=False: ✗ [DQ:condition_2]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
if bash -euo pipefail <<'DQ_PREDICATE'
bad=$(kubectl get pods -l app=quarantine -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null and .status.phase=="Running")]|if length==1 then .[0].metadata.name else error("expected one current Running quarantine Pod") end') || exit $?
test "$(kubectl exec "$bad" -c worker -- printenv ROUTE)" = retired
DQ_PREDICATE
then
  :
else
  code=$?
  printf '%s\n' 'The Running quarantine worker exposes ROUTE=retired: ✗ [DQ:condition_3]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
if bash -euo pipefail <<'DQ_PREDICATE'
good=$(kubectl get pods -l app=stable -o jsonpath='{.items[0].metadata.name}') || exit $?
test "$(kubectl get endpointslices -l kubernetes.io/service-name=departures -o json | jq -r '[.items[].endpoints[] | select(.conditions.ready==true) | .targetRef.name] | unique | .[]')" = "$good"
DQ_PREDICATE
then
  :
else
  code=$?
  printf '%s\n' 'Only the stable Pod is a ready departures endpoint: ✗ [DQ:condition_4]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
