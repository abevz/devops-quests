set -euo pipefail
cd ~/quest
source platform.env
curl -fsS -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" "$VAULT_ADDR/v1/sys/policies/acl/rail-reader" | jq -er .data.policy > observed-reader.hcl
python3 - <<'ACL_SCOPE'
import re
from pathlib import Path
p=Path('observed-reader.hcl').read_text()
p=re.sub(r'/\*.*?\*/','',p,flags=re.S)
p=re.sub(r'(?m)#.*$','',p)
assert re.fullmatch(r'\s*path\s+"secret/data/dispatch"\s*\{\s*capabilities\s*=\s*\[\s*"read"\s*\]\s*\}\s*',p), 'Keep only the named dispatch read policy'
ACL_SCOPE
test "$(curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" "$VAULT_ADDR/v1/secret/data/dispatch" | jq -er .data.data.value)" = north-secret
cat > capability-paths.json <<'DQ_ASSET'
{"paths": ["secret/data/dispatch", "secret/data/wrong", "secret/data/other", "sys/mounts"]}
DQ_ASSET
curl -fsS -X POST -H "X-Vault-Token: $VAULT_READER_TOKEN" -H 'Content-Type: application/json' --data-binary @capability-paths.json "$VAULT_ADDR/v1/sys/capabilities-self" | jq -e '(.data // .) | .["secret/data/dispatch"]==["read"] and .["secret/data/wrong"]==["deny"] and .["secret/data/other"]==["deny"] and .["sys/mounts"]==["deny"]' >/dev/null
