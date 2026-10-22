set -euo pipefail
cd ~/quest
remaining=$(kubectl get configmap station --ignore-not-found -o name)
test -z "$remaining"
remaining=$(kubectl get secret station-record --ignore-not-found -o name)
test -z "$remaining"
kubectl get secret control -o json > /tmp/control-live.json
python3 - <<'CONTROL_PROOF'
import json,hashlib
from pathlib import Path
c=json.loads(Path('/run/dq/facts/0/cleanup-contract.json').read_text());current=json.loads(Path('/tmp/control-live.json').read_text())
assert current['metadata']['uid']==c['control_uid']
assert hashlib.sha256(json.dumps(current['data'],sort_keys=True).encode()).hexdigest()==c['control_hash']
CONTROL_PROOF
