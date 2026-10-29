set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
hpa=$(timeout 2s kubectl get hpa board -o json 2>/dev/null || true)
check request 'board CPU request = 100m' '.spec.template.spec.containers[0].resources.requests.cpu=="100m"' "$board"
check limit 'board CPU limit = 200m' '.spec.template.spec.containers[0].resources.limits.cpu=="200m"' "$board"
check ready 'board readyReplicas = 2' '.status.readyReplicas==2' "$board"
check minimum 'HPA minReplicas = 1' '.spec.minReplicas==1' "$hpa"
check maximum 'HPA maxReplicas = 2' '.spec.maxReplicas==2' "$hpa"
check target 'HPA first metric averageUtilization = 50' '.spec.metrics[0].resource.target.averageUtilization==50' "$hpa"
check current 'HPA currentReplicas = 2' '.status.currentReplicas==2' "$hpa"
check desired 'HPA desiredReplicas = 2' '.status.desiredReplicas==2' "$hpa"
check metric 'HPA current resource metric utilization > 50' 'any(.status.currentMetrics[]?;.resource.current.averageUtilization>50)' "$hpa"
url=$(jq -r '.url // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
class=$(jq -r '.class // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
ns=$(jq -r '.namespace // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
gateway=$(timeout 2s kubectl get gateway station -o json 2>/dev/null || true)
route=$(timeout 2s kubectl get httproute board -o json 2>/dev/null || true)
policy=$(timeout 2s kubectl get networkpolicy board-ingress -o json 2>/dev/null || true)
if ! test -n "$class" || ! jq -e --arg class "$class" '.spec.gatewayClassName==$class' <<<"$gateway" >/dev/null 2>&1; then printf '%s\n' 'gateway class = gateway-target.json class: ✗ [DQ:gateway_class]'; failed=1; fi
check gateway_accepted 'gateway Accepted = True' 'any(.status.conditions[]?;.type=="Accepted" and .status=="True")' "$gateway"
check backend 'HTTPRoute first backend port = 8080' '.spec.rules[0].backendRefs[0].port==8080' "$route"
check resolved 'HTTPRoute parent ResolvedRefs = True' 'any(.status.parents[]?;any(.conditions[]?;.type=="ResolvedRefs" and .status=="True"))' "$route"
if ! test -n "$ns" || ! jq -e --arg ns "$ns" '.spec=={podSelector:{matchLabels:{app:"board"}},policyTypes:["Ingress"],ingress:[{from:[{namespaceSelector:{matchLabels:{"kubernetes.io/metadata.name":$ns}},podSelector:{matchLabels:{app:"gateway"}}}],ports:[{port:8080,protocol:"TCP"}]}]}' <<<"$policy" >/dev/null 2>&1; then printf '%s\n' 'board-ingress spec = supplied gateway policy: ✗ [DQ:policy]'; failed=1; fi
if ! test -n "$url" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 --header='Host: north.station.internal' "$url" 2>/dev/null)" = north-130; then printf '%s\n' 'gateway north.station.internal = north-130: ✗ [DQ:gateway_http]'; failed=1; fi
if timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 2 http://board:8080 >/dev/null 2>&1; then printf '%s\n' 'direct board:8080 request fails: ✗ [DQ:direct_denied]'; failed=1; fi
if ! test -n "$url" || timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 2 --header='Host: closed.station.internal' "$url" >/dev/null 2>&1; then printf '%s\n' 'gateway closed.station.internal request fails: ✗ [DQ:wrong_host]'; failed=1; fi
exit "$failed"
