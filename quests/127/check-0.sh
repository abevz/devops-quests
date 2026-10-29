set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
service=$(timeout 2s kubectl get service board -o json 2>/dev/null || true)
check port 'service board first port = 8080' '.spec.ports[0].port==8080' "$service"
check target_port 'service board first targetPort = 8080' '.spec.ports[0].targetPort==8080' "$service"
check selector 'service board selector = app board' '.spec.selector=={app:"board"}' "$service"
url=$(jq -r '.url // ""' /run/dq/facts/0/prometheus-target.json 2>/dev/null || true)
up=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=up%7Bjob%3D%22board%22%7D" 2>/dev/null || true)
sum=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=sum%28station_queue_depth%7Bjob%3D%22board%22%2Croute%3D%22north%22%7D%29" 2>/dev/null || true)
count=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=count%28station_queue_depth%7Bjob%3D%22board%22%2Croute%3D%22north%22%7D%29" 2>/dev/null || true)
targets=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "$url/api/v1/targets?state=active" 2>/dev/null || true)
for query in up sum count; do
  case "$query" in up) doc=$up; expected=1;; sum) doc=$sum; expected=7;; count) doc=$count; expected=2;; esac
  check "${query}_status" "$query query status = success" '.status=="success"' "$doc"
  check "${query}_count" "$query query returns one result" '(.data.result|length)==1' "$doc"
  if ! jq -e --arg expected "$expected" '.data.result[0].value[1]==$expected' <<<"$doc" >/dev/null 2>&1; then printf '%s\n' "$query query value = $expected: ✗ [DQ:${query}_value]"; failed=1; fi
done
check target_health 'one active board target is up with empty lastError' 'any(.data.activeTargets[]?;.labels.job=="board" and .health=="up" and .lastError=="")' "$targets"
exit "$failed"
