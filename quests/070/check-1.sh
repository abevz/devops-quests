set -euo pipefail
cd ~/quest
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.spec.source.repoURL==$url and .spec.source.path=="manifests" and .spec.source.targetRevision=="main" and .status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
kubectl rollout status deployment/board --timeout=3s >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-70
test "$(kubectl get secret route-secret -o jsonpath='{.data.value}' | base64 -d)" = north-secret
curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" -H 'Content-Type: application/json' --request POST --data '{"paths":["secret/data/dispatch","secret/data/unrelated","sys/mounts"]}' "$VAULT_ADDR/v1/sys/capabilities-self" | jq -e '."secret/data/dispatch"==["read"] and ."secret/data/unrelated"==["deny"] and ."sys/mounts"==["deny"]' >/dev/null
kubectl get deployment board -o json | jq -e '.spec.template.spec.containers[0].env==[{name:"ROUTE_SECRET",valueFrom:{secretKeyRef:{name:"route-secret",key:"value"}}}]' >/dev/null
