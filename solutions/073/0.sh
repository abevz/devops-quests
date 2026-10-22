set -euo pipefail
cd ~/quest
jq '.[0]' /run/dq/facts/0/audit-events.json > incident.json
cat > reader.hcl <<'DQ_ASSET'
path "secret/data/dispatch" { capabilities = ["read"] }
DQ_ASSET
source platform.env
jq -n --rawfile policy reader.hcl '{policy:$policy}' > reader-policy.json
curl -fsS -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H 'Content-Type: application/json' --request PUT --data-binary @reader-policy.json "$VAULT_ADDR/v1/sys/policies/acl/rail-reader" >/dev/null
