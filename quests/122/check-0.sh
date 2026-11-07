set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
baseline=$(cat /run/dq/facts/0/baseline-commit 2>/dev/null || true)
head=$(git -C repository rev-parse HEAD 2>/dev/null || true)
failed=0
if ! test -n "$baseline" || ! git -C repository merge-base --is-ancestor "$baseline" HEAD >/dev/null 2>&1; then printf '%s\n' 'baseline-commit is ancestor of HEAD: ✗ [DQ:ancestor]'; failed=1; fi
if ! test -n "$head" || ! test -n "$baseline" || test "$head" = "$baseline"; then printf '%s\n' 'HEAD differs from baseline-commit: ✗ [DQ:changed]'; failed=1; fi
if ! test -n "$head" || ! test "$(git -C repository ls-remote origin refs/heads/main 2>/dev/null | cut -f1)" = "$head"; then printf '%s\n' 'origin/main = HEAD: ✗ [DQ:origin]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
apps=$(kubectl get application parent board -o json 2>/dev/null || true)
app=$(jq -c '[.items[]?|select(.metadata.name=="board")][0] // {}' <<<"$apps" 2>/dev/null || true)
failed=0
child=$(git -C repository show HEAD:apps/child.yaml 2>/dev/null | python3 -c 'import json,sys,yaml; json.dump(yaml.safe_load(sys.stdin),sys.stdout)' 2>/dev/null || true)
check 'Git child kind = Application [DQ:child_kind]' '.kind=="Application"' "$child"
check 'Git child name = board [DQ:child_name]' '.metadata.name=="board"' "$child"
check 'Git child source path = manifests [DQ:child_source]' 'def same_dir($want): if type!="string" then false elif startswith("/") then false else (split("/") | map(select(.!="" and .!="."))) as $parts | ($parts | all(.!="..")) and ($parts | join("/")==$want) end; (.spec.source.path | same_dir("manifests"))' "$child"
check 'child Application project = station [DQ:project]' '.spec.project=="station"' "$app"
if ! jq -e --arg ns "$DQ_NAMESPACE" '.spec.destination.namespace==$ns' <<<"$app" >/dev/null 2>&1; then printf '%s\n' 'child Application destination = bay namespace: ✗ [DQ:destination]'; failed=1; fi
check 'child Application source path = manifests [DQ:source]' 'def same_dir($want): if type!="string" then false elif startswith("/") then false else (split("/") | map(select(.!="" and .!="."))) as $parts | ($parts | all(.!="..")) and ($parts | join("/")==$want) end; (.spec.source.path | same_dir("manifests"))' "$app"
if ! jq -e --arg ns "$DQ_NAMESPACE" '.metadata.annotations["argocd.argoproj.io/tracking-id"]==($ns+"_parent:argoproj.io/Application:"+$ns+"/board")' <<<"$app" >/dev/null 2>&1; then printf '%s\n' 'child Application tracking-id = parent tracking ID: ✗ [DQ:tracking]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
baseline=$(cat /run/dq/facts/0/baseline-commit 2>/dev/null || true)
head=$(git -C repository rev-parse HEAD 2>/dev/null || true)
apps=$(kubectl get application parent board -o json 2>/dev/null || true)
failed=0
for name in parent board; do
  app=$(jq -c --arg name "$name" '[.items[]?|select(.metadata.name==$name)][0] // {}' <<<"$apps" 2>/dev/null || true)
  check "application/$name sync status = Synced [DQ:sync_${name}]" '.status.sync.status=="Synced"' "$app"
  if ! test -n "$head" || ! jq -e --arg rev "$head" '.status.sync.revision==$rev' <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/$name revision = HEAD: ✗ [DQ:revision_${name}]"; failed=1; fi
done
check 'application/board health = Healthy [DQ:health]' '.status.health.status=="Healthy"' "$app"
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
apps=$(kubectl get application parent board -o json 2>/dev/null || true)
failed=0
parent=$(jq -c '[.items[]?|select(.metadata.name=="parent")][0] // {}' <<<"$apps" 2>/dev/null || true)
uid=$(cat /run/dq/facts/0/parent-uid 2>/dev/null || true)
if ! test -n "$uid" || ! jq -e --arg uid "$uid" '.metadata.uid==$uid' <<<"$parent" >/dev/null 2>&1; then printf '%s\n' 'parent Application UID = parent-uid: ✗ [DQ:parent_uid]'; failed=1; fi
check 'parent Application source path = apps [DQ:parent_path]' '.spec.source.path=="apps"' "$parent"
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
board=$(kubectl get deployment board -o json 2>/dev/null || true)
failed=0
check 'deployment/board readyReplicas = 1 [DQ:ready]' '.status.readyReplicas==1' "$board"
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-122; then printf '%s\n' 'board:8080 = north-122: ✗ [DQ:http]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
