set -euo pipefail
cd ~/quest
kubectl rollout status deployment/stable --timeout=3s
bad=$(kubectl get pods -l app=quarantine -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null and .status.phase=="Running")]|if length==1 then .[0].metadata.name else error("expected one current Running quarantine Pod") end')
kubectl get pod "$bad" -o json | jq -e '.status.phase=="Running" and any(.status.conditions[]; .type=="Ready" and .status=="False")' >/dev/null
test "$(kubectl exec "$bad" -- printenv ROUTE)" = retired
good=$(kubectl get pods -l app=stable -o jsonpath='{.items[0].metadata.name}')
test "$(kubectl get endpointslices -l kubernetes.io/service-name=departures -o json | jq -r '[.items[].endpoints[] | select(.conditions.ready==true) | .targetRef.name] | unique | .[]')" = "$good"
