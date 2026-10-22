set -euo pipefail
cd ~/quest
cat > reader.hcl <<'DQ_ASSET'
path "secret/data/dispatch" { capabilities = ["read"] }
DQ_ASSET
source platform.env
curl -fsS -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H "Content-Type: application/json" --request PUT --data "$(jq -n --rawfile policy reader.hcl '{policy:$policy}')" "$VAULT_ADDR/v1/sys/policies/acl/rail-reader" >/dev/null
bash sync-secret.sh
kubectl rollout status deployment/relay --timeout=90s
