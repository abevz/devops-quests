set -euo pipefail
cd ~/quest
source platform.env
curl -fsS "$VAULT_ADDR/v1/sys/seal-status" | jq -e --arg id "$(cat /run/dq/facts/0/original-cluster-id)" '.initialized==true and .sealed==false and .cluster_id==$id and .t==2 and .n==3' >/dev/null
test "$(curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" "$VAULT_ADDR/v1/secret/data/dispatch" | jq -er .data.data.value)" = north-secret
test "$(curl -sS -o /dev/null -w '%{http_code}' -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" "$VAULT_ADDR/v1/secret/data/dispatch")" = 403
test "$(stat -c %a unseal-shares.json)" = 600
