set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
station=$(timeout 2s kubectl get stationboard station -o json 2>/dev/null || true)
uid=$(jq -r '.metadata.uid // ""' <<<"$station" 2>/dev/null || true)
for resource in deployment/board configmap/board-route service/board; do
  object=$(timeout 2s kubectl get "$resource" -o json 2>/dev/null || true)
  if ! test -n "$uid" || ! jq -e --arg uid "$uid" 'any(.metadata.ownerReferences[]?;.apiVersion=="training.devops-quests.local/v1" and .kind=="StationBoard" and .name=="station" and .uid==$uid and .controller==true)' <<<"$object" >/dev/null 2>&1; then marker=${resource//\//_}; marker=${marker//-/_}; printf '%s\n' "$resource controller owner = station UID: ✗ [DQ:owner_$marker]"; failed=1; fi
done
check route 'station spec.route = north-116' '.spec.route=="north-116"' "$station"
check generation 'station observedGeneration = generation' '.status.observedGeneration==.metadata.generation and .metadata.generation!=null' "$station"
check station_ready 'station ready = true' '.status.ready==true' "$station"
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
check label 'board controller label = station-board' '.metadata.labels["devops-quests.controller"]=="station-board"' "$board"
check ready 'board readyReplicas = 1' '.status.readyReplicas==1' "$board"
config=$(timeout 2s kubectl get configmap board-route -o json 2>/dev/null || true)
check data 'board-route index.html = north-116 and newline' '.data["index.html"]=="north-116\n"' "$config"
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-116; then printf '%s\n' 'board:8080 = north-116: ✗ [DQ:http]'; failed=1; fi
exit "$failed"
