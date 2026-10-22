set -euo pipefail
cd ~/quest
volume=$(jq -r .volume /run/dq/facts/0/volume-contract.json)
python3 - <<'RECLAIM_PATCH'
import json
from pathlib import Path
c=json.loads(Path('/run/dq/facts/0/volume-contract.json').read_text());old=Path('/run/dq/facts/0/original-claim-uid').read_text().strip()
Path('/tmp/rebind.json').write_text(json.dumps([{'op':'test','path':'/metadata/uid','value':c['pv_uid']},{'op':'test','path':'/spec/claimRef/uid','value':old},{'op':'remove','path':'/spec/claimRef'}]))
RECLAIM_PATCH
kubectl patch pv "$volume" --type=json --patch-file /tmp/rebind.json
kubectl rollout status deployment/board --timeout=90s
