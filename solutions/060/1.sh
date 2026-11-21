set -euo pipefail
cd ~/quest
release=$(cat fleet-release.txt)
kubectl patch configmap relay-release --type=merge -p "$(jq -n --arg release "$release" '{data:{revision:$release}}')"
python3 - <<'DQ_ENV'
from pathlib import Path
import yaml

path = Path('deployment.yaml')
deployment = yaml.safe_load(path.read_text())
worker = next(c for c in deployment['spec']['template']['spec']['containers'] if c['name'] == 'worker')
entry = next(item for item in worker['env'] if item['name'] == 'RELEASE')
entry.pop('value', None)
entry['valueFrom'] = {'configMapKeyRef': {'name': 'relay-release', 'key': 'revision'}}
path.write_text(yaml.safe_dump(deployment, sort_keys=False))
DQ_ENV
kubectl apply -f deployment.yaml
kubectl rollout status deployment/relay --timeout=90s
