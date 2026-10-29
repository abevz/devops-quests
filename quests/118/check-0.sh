set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
if ! jq -e '.fault=="selector"' diagnosis.json >/dev/null 2>&1; then printf '%s\n' 'diagnosis.json fault = selector: ✗'; failed=1; fi
service=$(kubectl get service board -o json 2>/dev/null || true)
check 'service/board selector = app:board' '.spec.selector=={app:"board"}' "$service"
endpoints=$(kubectl get endpointslices -l kubernetes.io/service-name=board -o json 2>/dev/null || true)
check 'service/board EndpointSlice has a ready endpoint' 'any(.items[].endpoints[]?;.conditions.ready==true)' "$endpoints"
ip=$(kubectl get pod -l app=board -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
if ! test -n "$ip" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "http://$ip:8080" 2>/dev/null)" = north-118; then printf '%s\n' 'board Pod IP:8080 = north-118: ✗'; failed=1; fi
vip=$(jq -r '.spec.clusterIP // ""' <<<"$service" 2>/dev/null || true)
if ! test -n "$vip" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "http://$vip:8080" 2>/dev/null)" = north-118; then printf '%s\n' 'board Service VIP:8080 = north-118: ✗'; failed=1; fi
proxy=$(cat /run/dq/facts/0/proxy-observation.json 2>/dev/null || true)
check 'proxy observation ready = true' '.ready==true' "$proxy"
check 'proxy observation mode = iptables, nftables or ipvs' '.mode=="iptables" or .mode=="nftables" or .mode=="ipvs"' "$proxy"
exit "$failed"
