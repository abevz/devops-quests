set -euo pipefail
cd ~/quest
source platform.env
failed=0
app=$(kubectl get application board -o json 2>/dev/null || true)
rev=$(cat /run/dq/facts/0/baseline-commit 2>/dev/null || true)
check() { local label=$1 expression=$2; if ! jq -e --arg rev "$rev" --arg url "$GIT_URL" "$expression" <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/board $label: ✗"; failed=1; fi; }
check 'repoURL = GIT_URL [DQ:repo]' '.spec.source.repoURL==$url'
check 'path = manifests [DQ:path]' '.spec.source.path=="manifests"'
check 'targetRevision = main [DQ:target]' '.spec.source.targetRevision=="main"'
check 'selfHeal = true [DQ:selfheal]' '.spec.syncPolicy.automated.selfHeal==true'
check 'prune = true [DQ:prune]' '.spec.syncPolicy.automated.prune==true'
check 'sync status = Synced [DQ:synced]' '.status.sync.status=="Synced"'
if ! test -n "$rev"; then printf '%s\n' 'baseline-commit exists: ✗ [DQ:baseline]'; failed=1; fi
check 'sync revision = baseline-commit [DQ:baseline_revision]' '.status.sync.revision==$rev'
exit "$failed"
