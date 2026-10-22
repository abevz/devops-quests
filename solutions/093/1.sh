set -euo pipefail
cd ~/quest
source platform.env
for i in 0 1; do
 jq -n --arg key "$(jq -er ".[$i]" unseal-shares.json)" '{key:$key}' > unseal-request.json
 chmod 600 unseal-request.json
 curl -fsS -H 'Content-Type: application/json' --request PUT --data-binary @unseal-request.json "$VAULT_ADDR/v1/sys/unseal" > unseal-status.json
done
rm unseal-request.json
