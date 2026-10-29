set -euo pipefail
cd ~/quest
source platform.env
failed=0
if ! git -C repository fetch origin main >/dev/null 2>&1; then printf '%s\n' 'git fetch origin main: ✗'; failed=1; fi
rev=$(cat release-commit 2>/dev/null || true)
if ! test -n "$rev" || ! test "$(git -C repository rev-parse origin/main 2>/dev/null)" = "$rev"; then printf '%s\n' 'origin/main = release-commit: ✗'; failed=1; fi
app=$(kubectl get application board -o json 2>/dev/null || true)
check_app() { local label=$1 expression=$2; if ! jq -e --arg rev "$rev" --arg url "$GIT_URL" "$expression" <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/board $label: ✗"; failed=1; fi; }
check_app 'repoURL = GIT_URL' '.spec.source.repoURL==$url'
check_app 'path = manifests' '.spec.source.path=="manifests"'
check_app 'targetRevision = main' '.spec.source.targetRevision=="main"'
check_app 'selfHeal = true' '.spec.syncPolicy.automated.selfHeal==true'
check_app 'prune = true' '.spec.syncPolicy.automated.prune==true'
check_app 'sync status = Synced' '.status.sync.status=="Synced"'
check_app 'health status = Healthy' '.status.health.status=="Healthy"'
check_app 'sync revision = release-commit' '.status.sync.revision==$rev'
if ! kubectl rollout status deployment/board --timeout=3s >/dev/null 2>&1; then printf '%s\n' 'deployment/board rollout complete: ✗'; failed=1; fi
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-100; then printf '%s\n' 'board:8080 = north-100: ✗'; failed=1; fi
image=$(jq -er .image /run/dq/facts/0/private-release.json 2>/dev/null || true)
board=$(kubectl get deployment board -o json 2>/dev/null || true)
check_board() { local label=$1 expression=$2; if ! jq -e --arg image "$image" "$expression" <<<"$board" >/dev/null 2>&1; then printf '%s\n' "deployment/board $label: ✗"; failed=1; fi; }
if ! test -n "$image"; then printf '%s\n' 'private-release.json image exists: ✗'; failed=1; fi
check_board 'first image = frozen image' '.spec.template.spec.containers[0].image==$image'
check_board 'first imagePullPolicy = Always' '.spec.template.spec.containers[0].imagePullPolicy=="Always"'
check_board 'imagePullSecrets = [registry-pull]' '.spec.template.spec.imagePullSecrets==[{name:"registry-pull"}]'
check_board 'first env = ROUTE_SECRET from route-secret/value only' '.spec.template.spec.containers[0].env==[{name:"ROUTE_SECRET",valueFrom:{secretKeyRef:{name:"route-secret",key:"value"}}}]'
if ! test "$(kubectl get secret route-secret -o json 2>/dev/null | jq -er .data.value 2>/dev/null | base64 -d 2>/dev/null)" = north-secret; then printf '%s\n' 'secret/route-secret value = north-secret: ✗'; failed=1; fi
digest=${image##*@}
if ! test -n "$image" || ! kubectl get pods -l app=board -o json 2>/dev/null | jq -e --arg digest "$digest" 'any(.items[];any(.status.containerStatuses[]?;.ready==true and (.imageID|contains($digest))))' >/dev/null 2>&1; then printf '%s\n' 'ready board container imageID contains frozen digest: ✗'; failed=1; fi
umask 077
header=$(mktemp)
trap 'rm -f "$header"' EXIT
printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN" > "$header"
if ! curl -fsS --max-time 3 -H @"$header" "$VAULT_ADDR/v1/secret/data/dispatch" 2>/dev/null | jq -e '.data.data.value=="north-secret"' >/dev/null 2>&1; then printf '%s\n' 'Vault reader dispatch value = north-secret: ✗'; failed=1; fi
if ! test "$(curl -sS --max-time 3 -o /dev/null -w '%{http_code}' -H @"$header" "$VAULT_ADDR/v1/secret/data/other" 2>/dev/null)" = 403; then printf '%s\n' 'Vault reader other path HTTP 403: ✗'; failed=1; fi
manifest=$(git -C repository show origin/main:manifests/board.json 2>/dev/null || true)
if ! jq -e --arg image "$image" '.spec.template.spec.containers[0].image==$image' <<<"$manifest" >/dev/null 2>&1; then printf '%s\n' 'Git manifest first image = frozen image: ✗'; failed=1; fi
if ! jq -e '.spec.template.spec.containers[0].env[0].valueFrom.secretKeyRef.name=="route-secret"' <<<"$manifest" >/dev/null 2>&1; then printf '%s\n' 'Git manifest first env secret reference = route-secret: ✗'; failed=1; fi
exit "$failed"
