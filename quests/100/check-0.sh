set -euo pipefail
cd ~/quest
source platform.env
failed=0
app=$(kubectl get application board -o json 2>/dev/null || true)
rev=$(cat /run/dq/facts/0/baseline-commit 2>/dev/null || true)
check() { local label=$1 expression=$2; if ! jq -e --arg rev "$rev" --arg url "$GIT_URL" "$expression" <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/board $label: ✗"; failed=1; fi; }
check 'repoURL = GIT_URL' '.spec.source.repoURL==$url'
check 'path = manifests' '.spec.source.path=="manifests"'
check 'targetRevision = main' '.spec.source.targetRevision=="main"'
check 'selfHeal = true' '.spec.syncPolicy.automated.selfHeal==true'
check 'prune = true' '.spec.syncPolicy.automated.prune==true'
check 'sync status = Synced' '.status.sync.status=="Synced"'
if ! test -n "$rev"; then printf '%s\n' 'baseline-commit exists: ✗'; failed=1; fi
check 'sync revision = baseline-commit' '.status.sync.revision==$rev'
exit "$failed"
