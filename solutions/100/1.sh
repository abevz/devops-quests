set -euo pipefail
cd ~/quest
source platform.env
cat > reader.hcl <<'POLICY'
path "secret/data/dispatch" { capabilities = ["read"] }
POLICY
jq -n --rawfile policy reader.hcl '{policy:$policy}' > policy-request.json
curl -fsS -X PUT -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H 'Content-Type: application/json' --data-binary @policy-request.json "$VAULT_ADDR/v1/sys/policies/acl/rail-reader"
bash sync-secret.sh
source platform.env
kubectl create secret docker-registry registry-pull --docker-server="$REGISTRY" --docker-username="$REGISTRY_USER" --docker-password="$REGISTRY_PASSWORD" --dry-run=client -o json | kubectl apply -f -
kubectl rollout restart deployment/board
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" '.status.sync.revision==$rev and .status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null; then break; fi
 sleep 1
done
kubectl rollout status deployment/board --timeout=60s
