set -euo pipefail
cd ~/quest
source platform.env
curl -fsS "$VAULT_ADDR/v1/sys/seal-status" > initial-seal-status.json
