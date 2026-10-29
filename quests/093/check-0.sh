set -euo pipefail
cd ~/quest
source platform.env
if ! curl -fsS "$VAULT_ADDR/v1/sys/init" 2>/dev/null | jq -e '.initialized == true' >/dev/null 2>&1; then
  printf '%s\n' 'sys/init initialized = true: ✗'
  exit 1
fi
