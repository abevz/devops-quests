set -euo pipefail
cd ~/quest
cat > reader.hcl <<'DQ_ASSET'
path "secret/data/dispatch" { capabilities = ["read"] }
DQ_ASSET
source platform.env
jq -n --rawfile policy reader.hcl '{policy:$policy}' > reader-policy.json
curl -fsS -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H 'Content-Type: application/json' --request PUT --data-binary @reader-policy.json "$VAULT_ADDR/v1/sys/policies/acl/rail-reader" >/dev/null
bash sync-secret.sh
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if kubectl get application board -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null && kubectl rollout status deployment/board --timeout=2s >/dev/null 2>&1; then break; fi
 sleep 1
done
