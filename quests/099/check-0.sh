set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository rev-parse origin/main)" = "$(cat release-commit)"
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg url "$GIT_URL" '.spec.source.repoURL==$url and .spec.source.path=="manifests" and .spec.source.targetRevision=="main"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.spec.syncPolicy.automated.selfHeal==true and .spec.syncPolicy.automated.prune==true and .status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 http://board:8080)" = north-99
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
image=$(jq -er .image /run/dq/facts/0/private-release.json)
kubectl get deployment board -o json | jq -e --arg image "$image" '.spec.template.spec.containers[0].image==$image and .spec.template.spec.containers[0].imagePullPolicy=="Always" and .spec.template.spec.imagePullSecrets==[{name:"registry-pull"}]' >/dev/null
digest=${image##*@}
kubectl get pods -l app=board -o json | jq -e --arg digest "$digest" 'any(.items[];any(.status.containerStatuses[]?;.ready==true and (.imageID|contains($digest))))' >/dev/null
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
image=$(jq -er .image /run/dq/facts/0/private-release.json)
kubectl get deployment board -o json | jq -e --arg image "$image" '.spec.template.spec.containers[0].env==[{name:"ROUTE_SECRET",valueFrom:{secretKeyRef:{name:"route-secret",key:"value"}}}]' >/dev/null
kubectl get secret route-secret -o json | jq -er .data.value | base64 -d | grep -qx north-secret
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
test "$(stat -c %a station-token)" = 600
test "$(cat station-token)" != "$VAULT_READER_TOKEN"
curl -fsS -H "X-Vault-Token: $(cat station-token)" "$VAULT_ADDR/v1/secret/data/dispatch" | jq -e '.data.data.value=="north-secret"' >/dev/null
curl -fsS -H "X-Vault-Token: $(cat station-token)" "$VAULT_ADDR/v1/auth/token/lookup-self" | jq -e '.data.policies==["default","rail-reader"] and .data.ttl>0 and .data.ttl<=600' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
test "$(curl -sS -o /dev/null -w '%{http_code}' -H "X-Vault-Token: $VAULT_READER_TOKEN" "$VAULT_ADDR/v1/secret/data/dispatch")" = 403
)
[ $? -eq 0 ] || failed=1
exit "$failed"
