set -euo pipefail
cd ~/quest
source platform.env
curl -fsS "$VAULT_ADDR/v1/sys/seal-status" | jq -e '.initialized==true and .sealed==false and .t==2 and .n==3' >/dev/null
test "$(stat -c %a unseal-shares.json)" = 600
jq -e 'length==2 and all(.[];type=="string")' unseal-shares.json >/dev/null
test "$(curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" "$VAULT_ADDR/v1/secret/data/dispatch" | jq -er .data.data.value)" = north-secret
