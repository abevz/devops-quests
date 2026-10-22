set -euo pipefail
cd ~/quest
class=$(jq -r .class /run/dq/facts/0/gateway-target.json)
url=$(jq -r .url /run/dq/facts/0/gateway-target.json)
kubectl get gateway station -o json | jq -e --arg class "$class" '. as $gw | .spec.gatewayClassName==$class and any(.status.conditions[]?;.type=="Accepted" and .status=="True" and .observedGeneration==$gw.metadata.generation)' >/dev/null
kubectl get httproute board -o json | jq -e '.spec.parentRefs[0].name=="station" and .spec.hostnames==["north.station.internal"] and .spec.rules[0].backendRefs[0].name=="board" and .spec.rules[0].backendRefs[0].port==8080 and any(.status.parents[]?;any(.conditions[]?;.type=="Accepted" and .status=="True") and any(.conditions[]?;.type=="ResolvedRefs" and .status=="True"))' >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 --header='Host: north.station.internal' "$url")" = north-113
if kubectl exec deployment/client -- wget -qO- -T 3 --header='Host: closed.station.internal' "$url" >/dev/null 2>&1; then exit 1; fi
