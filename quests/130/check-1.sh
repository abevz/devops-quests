set -euo pipefail
cd ~/quest
kubectl get deployment board -o json | jq -e '.spec.template.spec.containers[0].resources.requests.cpu=="100m" and .spec.template.spec.containers[0].resources.limits.cpu=="200m" and .status.readyReplicas==2' >/dev/null
kubectl get hpa board -o json | jq -e '.spec.minReplicas==1 and .spec.maxReplicas==2 and .spec.metrics[0].resource.target.averageUtilization==50 and .status.currentReplicas==2 and .status.desiredReplicas==2 and any(.status.currentMetrics[]?;.resource.current.averageUtilization>50)' >/dev/null
url=$(jq -r .url /run/dq/facts/0/gateway-target.json)
class=$(jq -r .class /run/dq/facts/0/gateway-target.json)
ns=$(jq -r .namespace /run/dq/facts/0/gateway-target.json)
kubectl get gateway station -o json | jq -e --arg class "$class" '.spec.gatewayClassName==$class and any(.status.conditions[]?;.type=="Accepted" and .status=="True")' >/dev/null
kubectl get httproute board -o json | jq -e '.spec.rules[0].backendRefs[0].port==8080 and any(.status.parents[]?;any(.conditions[]?;.type=="ResolvedRefs" and .status=="True"))' >/dev/null
kubectl get networkpolicy board-ingress -o json | jq -e --arg ns "$ns" '.spec=={podSelector:{matchLabels:{app:"board"}},policyTypes:["Ingress"],ingress:[{from:[{namespaceSelector:{matchLabels:{"kubernetes.io/metadata.name":$ns}},podSelector:{matchLabels:{app:"gateway"}}}],ports:[{port:8080,protocol:"TCP"}]}]}' >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 --header='Host: north.station.internal' "$url")" = north-130
if kubectl exec deployment/client -- wget -qO- -T 2 http://board:8080 >/dev/null 2>&1; then exit 1; fi
if kubectl exec deployment/client -- wget -qO- -T 2 --header='Host: closed.station.internal' "$url" >/dev/null 2>&1; then exit 1; fi
