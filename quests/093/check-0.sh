set -euo pipefail
cd ~/quest
source platform.env
curl -fsS "$VAULT_ADDR/v1/sys/init" | jq -e ".initialized==true" >/dev/null
