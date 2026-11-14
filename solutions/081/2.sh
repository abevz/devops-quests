set -euo pipefail
cd ~/quest
tofu output -json delivery > delivery.json
kubectl create configmap delivery --from-literal=release="$(jq -r .release delivery.json)" --from-file=contract=delivery.json --dry-run=client -o yaml > delivery-config.yaml
kubectl apply -f delivery-config.yaml
python3 - <<'DQ_RELAY'
from pathlib import Path
import yaml
p=Path('deployment.yaml');document=yaml.safe_load(p.read_text())
worker=next(c for c in document['spec']['template']['spec']['containers'] if c['name']=='worker')
worker['env']=[{'name':'RELEASE','valueFrom':{'configMapKeyRef':{'name':'delivery','key':'release'}}},{'name':'DELIVERY_CONTRACT','valueFrom':{'configMapKeyRef':{'name':'delivery','key':'contract'}}}]
p.write_text(yaml.safe_dump(document,sort_keys=False))
DQ_RELAY
kubectl apply -f deployment.yaml
kubectl rollout status deployment/relay --timeout=90s
