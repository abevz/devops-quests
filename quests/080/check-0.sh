set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
source platform.env
revision=$(cat /run/dq/facts/0/baseline-commit 2>/dev/null || true)
app=$(kubectl get application board -o json 2>/dev/null || true)
check_app() { local label=$1 expression=$2; if ! jq -e --arg url "$GIT_URL" --arg revision "$revision" "$expression" <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/board $label: ✗"; failed=1; fi; }
check_app 'repoURL = GIT_URL' '.spec.source.repoURL==$url'
check_app 'source path = manifests' '.spec.source.path=="manifests"'
check_app 'targetRevision = main' '.spec.source.targetRevision=="main"'
check_app 'sync status = Synced' '.status.sync.status=="Synced"'
if ! test -n "$revision"; then printf '%s\n' 'expected Git revision exists: ✗'; failed=1; fi
check_app 'sync revision = expected revision' '.status.sync.revision==$revision'
check_app 'selfHeal = true' '.spec.syncPolicy.automated.selfHeal==true'
board=$(kubectl get deployment board -o json 2>/dev/null || true)
check 'deployment/board imagePullSecrets = [registry-pull]' '.spec.template.spec.imagePullSecrets==[{name:"registry-pull"}]' "$board"
check 'deployment/board imagePullPolicy = Always' '.spec.template.spec.containers[0].imagePullPolicy=="Always"' "$board"
exit "$failed"
