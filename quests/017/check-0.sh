set -euo pipefail
cd ~/quest
failed=0
if ! (
kubectl rollout status deployment/stable --timeout=3s
); then failed=1; fi
if ! (
bad=$(kubectl get pods -l app=quarantine -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null and .status.phase=="Running")]|if length==1 then .[0].metadata.name else error("expected one current Running quarantine Pod") end')
); then failed=1; fi
if ! (
bad=$(kubectl get pods -l app=quarantine -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null and .status.phase=="Running")]|if length==1 then .[0].metadata.name else error("expected one current Running quarantine Pod") end') || exit $?
kubectl get pod "$bad" -o json | jq -e '.status.phase=="Running" and any(.status.conditions[]; .type=="Ready" and .status=="False")' >/dev/null
); then failed=1; fi
if ! (
bad=$(kubectl get pods -l app=quarantine -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null and .status.phase=="Running")]|if length==1 then .[0].metadata.name else error("expected one current Running quarantine Pod") end') || exit $?
test "$(kubectl exec "$bad" -- printenv ROUTE)" = retired
); then failed=1; fi
if ! (
good=$(kubectl get pods -l app=stable -o jsonpath='{.items[0].metadata.name}') || exit $?
test "$(kubectl get endpointslices -l kubernetes.io/service-name=departures -o json | jq -r '[.items[].endpoints[] | select(.conditions.ready==true) | .targetRef.name] | unique | .[]')" = "$good"
); then failed=1; fi
exit "$failed"
