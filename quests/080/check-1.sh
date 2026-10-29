set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
source platform.env
revision=$(cat release-commit 2>/dev/null || true)
app=$(kubectl get application board -o json 2>/dev/null || true)
check_app() { local label=$1 expression=$2; if ! jq -e --arg url "$GIT_URL" --arg revision "$revision" "$expression" <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/board $label: ✗"; failed=1; fi; }
check_app 'repoURL = GIT_URL [DQ:repo]' '.spec.source.repoURL==$url'
check_app 'source path = manifests [DQ:path]' '.spec.source.path=="manifests"'
check_app 'targetRevision = main [DQ:target]' '.spec.source.targetRevision=="main"'
check_app 'sync status = Synced [DQ:synced]' '.status.sync.status=="Synced"'
if ! test -n "$revision"; then printf '%s\n' 'expected Git revision exists: ✗ [DQ:revision_exists]'; failed=1; fi
check_app 'sync revision = expected revision [DQ:revision]' '.status.sync.revision==$revision'
check_app 'selfHeal = true [DQ:selfheal]' '.spec.syncPolicy.automated.selfHeal==true'
check_app 'health = Healthy [DQ:health]' '.status.health.status=="Healthy"'
check_app 'prune = true [DQ:prune]' '.spec.syncPolicy.automated.prune==true'
if ! kubectl rollout status deployment/board --timeout=3s >/dev/null 2>&1; then printf '%s\n' 'deployment/board rollout complete: ✗ [DQ:rollout]'; failed=1; fi
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-80; then printf '%s\n' 'board:8080 = north-80: ✗ [DQ:http]'; failed=1; fi
image=$(jq -r '.image // ""' /run/dq/facts/0/private-release.json 2>/dev/null || true)
digest=${image##*@}
if ! test -n "$image"; then printf '%s\n' 'private-release.json image exists: ✗ [DQ:release_image]'; failed=1; fi
if ! git -C repository fetch origin main >/dev/null 2>&1; then printf '%s\n' 'git fetch origin main: ✗ [DQ:fetch]'; failed=1; fi
if ! test -n "$revision" || ! test "$(git -C repository rev-parse origin/main 2>/dev/null)" = "$revision"; then printf '%s\n' 'origin/main = release-commit: ✗ [DQ:origin]'; failed=1; fi
baseline=$(cat /run/dq/facts/0/baseline-commit 2>/dev/null || true)
if ! test -n "$revision" || ! test -n "$baseline" || test "$revision" = "$baseline"; then printf '%s\n' 'release-commit differs from baseline-commit: ✗ [DQ:changed]'; failed=1; fi
if ! test -n "$baseline" || ! git -C repository merge-base --is-ancestor "$baseline" origin/main >/dev/null 2>&1; then printf '%s\n' 'baseline-commit is ancestor of origin/main: ✗ [DQ:ancestor]'; failed=1; fi
manifest=$(git -C repository show origin/main:manifests/board.json 2>/dev/null || true)
if ! test -n "$image" || ! jq -e --arg image "$image" '.spec.template.spec.containers[0].image==$image' <<<"$manifest" >/dev/null 2>&1; then printf '%s\n' 'Git board first image = frozen image: ✗ [DQ:git_image]'; failed=1; fi
check 'Git board imagePullPolicy = Always [DQ:git_policy]' '.spec.template.spec.containers[0].imagePullPolicy=="Always"' "$manifest"
check 'Git board imagePullSecrets = [registry-pull] [DQ:git_secrets]' '.spec.template.spec.imagePullSecrets==[{name:"registry-pull"}]' "$manifest"
board=$(kubectl get deployment board -o json 2>/dev/null || true)
if ! test -n "$image" || ! jq -e --arg image "$image" '.spec.template.spec.containers[0].image==$image' <<<"$board" >/dev/null 2>&1; then printf '%s\n' 'live board first image = frozen image: ✗ [DQ:live_image]'; failed=1; fi
check 'live board imagePullPolicy = Always [DQ:live_policy]' '.spec.template.spec.containers[0].imagePullPolicy=="Always"' "$board"
if ! test -n "$image" || ! kubectl get pods -l app=board -o json 2>/dev/null | jq -e --arg digest "$digest" 'any(.items[];.metadata.deletionTimestamp==null and any(.status.containerStatuses[]?;.ready==true and (.imageID|contains($digest))))' >/dev/null 2>&1; then printf '%s\n' 'ready board Pod imageID contains frozen digest: ✗ [DQ:image_id]'; failed=1; fi
umask 077
config=$(mktemp)
trap 'rm -f "$config"' EXIT
printf 'user = "%s:%s"\n' "$REGISTRY_USER" "$REGISTRY_PASSWORD" > "$config"
if ! test -n "$image" || ! curl -fsS --max-time 4 --config "$config" --cacert registry-ca.crt -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' "https://$REGISTRY/v2/parcel/manifests/$digest" >/dev/null 2>&1; then printf '%s\n' 'authenticated registry serves frozen digest: ✗ [DQ:registry]'; failed=1; fi
exit "$failed"
