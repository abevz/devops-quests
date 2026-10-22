set -euo pipefail
cd ~/quest
source platform.env
jq -e --slurpfile events /run/dq/facts/0/audit-events.json 'keys==["operation","path","reason","request_id"] and .==$events[0][0]' incident.json >/dev/null
curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" -H 'Content-Type: application/json' --request POST --data '{"paths":["secret/data/dispatch","secret/data/other","sys/audit"]}' "$VAULT_ADDR/v1/sys/capabilities-self" | jq -e '."secret/data/dispatch"==["read"] and ."secret/data/other"==["deny"] and ."sys/audit"==["deny"]' >/dev/null
test "$(curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" "$VAULT_ADDR/v1/secret/data/dispatch" | jq -er .data.data.value)" = north-secret
