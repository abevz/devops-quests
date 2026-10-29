set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
dns_answer_has() {
  local result=$1 expected=$2
  awk -v expected="$expected" '
    /^[[:space:]]*Name([[:space:]]+[0-9]+)?:/ { answer=1; next }
    answer && /^[[:space:]]*Address([[:space:]]+[0-9]+)?:/ {
      sub(/^[^:]*:[[:space:]]*/, ""); split($0, fields, /[[:space:]]+/)
      if (fields[1] == expected) found=1
    }
    END { exit !found }
  ' <<<"$result"
}
services=$(kubectl get service board-internal board-headless board-node -o json 2>/dev/null | jq -c '[.items[] | {name:.metadata.name,uid:.metadata.uid,type:.spec.type,clusterIP:.spec.clusterIP,clusterIPs:.spec.clusterIPs,ports:.spec.ports}] | sort_by(.name)' 2>/dev/null || true)
original=$(cat /run/dq/facts/0/service-contracts.json 2>/dev/null || true)
for name in board-internal board-headless board-node; do
  for field in uid type clusterIP clusterIPs ports; do
    if ! jq -e --arg name "$name" --arg field "$field" --argjson original "$original" '([.[]|select(.name==$name)]|length)==1 and ([$original[]|select(.name==$name)]|length)==1 and ([.[]|select(.name==$name)][0][$field] == [$original[]|select(.name==$name)][0][$field])' <<<"$services" >/dev/null 2>&1; then printf '%s\n' "$name $field = service-contracts.json: ✗"; failed=1; fi
  done
done
if ! jq -e 'length==3' <<<"$services" >/dev/null 2>&1 || ! jq -e 'length==3' <<<"$original" >/dev/null 2>&1; then printf '%s\n' 'live and recorded Service counts = 3: ✗'; failed=1; fi
internal=$(kubectl get service board-internal -o json 2>/dev/null || true)
headless=$(kubectl get service board-headless -o json 2>/dev/null || true)
nodeport=$(kubectl get service board-node -o json 2>/dev/null || true)
check 'board-internal type = ClusterIP' '.spec.type=="ClusterIP"' "$internal"
check 'board-internal clusterIP != None' '.spec.clusterIP!="None" and .spec.clusterIP!=null' "$internal"
check 'board-internal selector = app:board' '.spec.selector=={app:"board"}' "$internal"
check 'board-headless clusterIP = None' '.spec.clusterIP=="None"' "$headless"
check 'board-headless selector = app:board' '.spec.selector=={app:"board"}' "$headless"
check 'board-node type = NodePort' '.spec.type=="NodePort"' "$nodeport"
check 'board-node selector = app:board' '.spec.selector=={app:"board"}' "$nodeport"
check 'board-node nodePort >= 30000' '.spec.ports[0].nodePort>=30000' "$nodeport"
for name in board-internal board-headless board-node; do
  if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "http://$name:8080" 2>/dev/null)" = north-106; then printf '%s\n' "$name:8080 = north-106: ✗"; failed=1; fi
done
node=$(kubectl config view --minify -o json 2>/dev/null | jq -r '.clusters[0].cluster.server | sub("^https://";"") | split(":")[0]' 2>/dev/null || true)
port=$(jq -r '.spec.ports[0].nodePort // ""' <<<"$nodeport" 2>/dev/null || true)
if ! test -n "$node" || ! test -n "$port" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "http://$node:$port" 2>/dev/null)" = north-106; then printf '%s\n' 'private node NodePort = north-106: ✗'; failed=1; fi
pod_ip=$(kubectl get pod -l app=board -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
lookup=''
if test -n "$pod_ip"; then
  if ! lookup=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- nslookup -type=A "board-headless.$DQ_NAMESPACE.svc.cluster.local." 2>/dev/null); then lookup=''; fi
fi
if ! test -n "$pod_ip" || ! dns_answer_has "$lookup" "$pod_ip"; then printf '%s\n' 'board-headless DNS answer = board Pod IP: ✗'; failed=1; fi
exit "$failed"
