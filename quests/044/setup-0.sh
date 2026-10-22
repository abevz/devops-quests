set -euo pipefail
cd ~/quest
cat > apply-policy.sh <<'DQ_ASSET'
#!/bin/bash
set -euo pipefail
cd ~/quest
source platform.env
python3 - <<'POLICY'
import json
from pathlib import Path
Path('policy.json').write_text(json.dumps({'policy':Path('reader.hcl').read_text()}))
POLICY
jq -e . policy.json >/dev/null
curl -fsS -X PUT -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H 'Content-Type: application/json' --data-binary @policy.json "$VAULT_ADDR/v1/sys/policies/acl/rail-reader" >/dev/null
DQ_ASSET
