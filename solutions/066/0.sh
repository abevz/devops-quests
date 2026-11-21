set -euo pipefail
cd ~/quest
source platform.env
jq --slurpfile c /run/dq/facts/0/release-catalog.json '{delete:[$c[0].obsolete]}' retention.json > corrected-retention.json
mv corrected-retention.json retention.json
cat > prune.sh <<'DQ_CONSTRUCT'
#!/bin/bash
set -euo pipefail
cd ~/quest
source platform.env
umask 077
header=$(mktemp)
trap 'rm -f "$header"' EXIT
python3 -I - > "$header" <<'PRIVATE_AUTH'
import base64,os
print('Authorization: Basic '+base64.b64encode((os.environ['REGISTRY_USER']+':'+os.environ['REGISTRY_PASSWORD']).encode()).decode())
PRIVATE_AUTH
python3 -I - <<'CHECK_PLAN'
import json,re
from pathlib import Path
catalog=json.loads(Path('/run/dq/facts/0/release-catalog.json').read_text())
plan=json.loads(Path('retention.json').read_text())
assert isinstance(plan['delete'],list)
assert set(plan['delete'])=={catalog['obsolete']}
assert all(re.fullmatch(r'sha256:[a-f0-9]{64}',d) for d in plan['delete'])
CHECK_PLAN
while IFS= read -r digest; do
 curl -fsS --max-time 3 --cacert registry-ca.crt -H @"$header" -X DELETE "https://$REGISTRY/v2/parcel/manifests/$digest" >/dev/null
done < <(jq -r '.delete|unique[]' retention.json)
DQ_CONSTRUCT
bash prune.sh
digest=$(jq -er .current /run/dq/facts/0/release-catalog.json)
docker pull "$REGISTRY/parcel@$digest" >/dev/null
docker tag "$REGISTRY/parcel@$digest" "$REGISTRY/parcel:current"
docker push "$REGISTRY/parcel:current" >/dev/null
