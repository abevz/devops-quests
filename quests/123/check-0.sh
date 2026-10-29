set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
ns=$(jq -r '.namespace // ""' /run/dq/facts/0/appset-target.json 2>/dev/null || true)
repo=$(jq -r '.repoURL // ""' /run/dq/facts/0/appset-target.json 2>/dev/null || true)
revision=$(cat /run/dq/facts/0/release-commit 2>/dev/null || true)
appset=$(kubectl -n "$ns" get applicationset station -o json 2>/dev/null || true)
uid=$(jq -r '.metadata.uid // ""' <<<"$appset" 2>/dev/null || true)
if ! test -n "$ns"; then printf '%s\n' 'appset-target.json namespace exists: ✗ [DQ:namespace]'; failed=1; fi
if ! test -n "$repo"; then printf '%s\n' 'appset-target.json repoURL exists: ✗ [DQ:repo]'; failed=1; fi
if ! test -n "$revision"; then printf '%s\n' 'release-commit exists: ✗ [DQ:revision]'; failed=1; fi
if ! test -n "$uid"; then printf '%s\n' 'applicationset/station UID exists: ✗ [DQ:uid]'; failed=1; fi
check 'applicationset template path = stations/{{.station}} [DQ:path]' '.spec.template.spec.source.path=="stations/{{.station}}"' "$appset"
check 'applicationset goTemplate = true [DQ:gotemplate]' '.spec.goTemplate==true' "$appset"
check 'applicationset generator stations = [north,south] [DQ:stations]' '(.spec.generators[0].list.elements|map(.station))==["north","south"]' "$appset"
apps=$(kubectl -n "$ns" get application north south -o json 2>/dev/null || true)
check 'generated Applications count = 2 [DQ:count]' '.items|length==2' "$apps"
for station in north south; do
  app=$(jq -c --arg station "$station" '[.items[]?|select(.metadata.name==$station)][0] // {}' <<<"$apps" 2>/dev/null || true)
  check "application/$station sync = Synced [DQ:sync_${station}]" '.status.sync.status=="Synced"' "$app"
  if ! test -n "$revision" || ! jq -e --arg rev "$revision" '.status.sync.revision==$rev' <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/$station revision = release-commit: ✗ [DQ:revision_${station}]"; failed=1; fi
  check "application/$station health = Healthy [DQ:health_${station}]" '.status.health.status=="Healthy"' "$app"
  check "application/$station project = station [DQ:project_${station}]" '.spec.project=="station"' "$app"
  if ! test -n "$repo" || ! jq -e --arg repo "$repo" '.spec.source.repoURL==$repo' <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/$station repoURL = appset-target.json: ✗ [DQ:repo_${station}]"; failed=1; fi
  if ! jq -e --arg station "$station" '.spec.source.path==("stations/"+$station)' <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/$station path = stations/$station: ✗ [DQ:source_${station}]"; failed=1; fi
  if ! jq -e --arg bay "$DQ_NAMESPACE" '.spec.destination.namespace==$bay' <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/$station destination = bay namespace: ✗ [DQ:destination_${station}]"; failed=1; fi
  if ! test -n "$uid" || ! jq -e --arg uid "$uid" 'any(.metadata.ownerReferences[]?;.uid==$uid and .kind=="ApplicationSet")' <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/$station owned by ApplicationSet: ✗ [DQ:owner_${station}]"; failed=1; fi
  deployment=$(kubectl get deployment "$station" -o json 2>/dev/null || true)
  check "deployment/$station readyReplicas = 1 [DQ:ready_${station}]" '.status.readyReplicas==1' "$deployment"
  if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s "deployment/$station" -- wget -qO- -T 3 "http://$station:8080" 2>/dev/null)" = "$station-123"; then printf '%s\n' "$station:8080 = $station-123: ✗ [DQ:http_${station}]"; failed=1; fi
done
exit "$failed"
