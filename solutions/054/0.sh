set -euo pipefail
cd ~/quest

source platform.env
python3 -I - <<'VERSION'
from pathlib import Path
import yaml
p=Path('repository/manifests/route.yaml');cm=yaml.safe_load(p.read_text());cm['data']['route']='drifted'
p.write_text(yaml.safe_dump(cm,sort_keys=False))
next_map={'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'relay-route-approved'},'immutable':True,'data':{'route':'north'}}
Path('repository/manifests/approved-route.yaml').write_text(yaml.safe_dump(next_map,sort_keys=False))
p=Path('repository/manifests/relay.yaml');d=yaml.safe_load(p.read_text())
d['spec']['template']['spec']['containers'][0]['env'][0]['valueFrom']['configMapKeyRef']['name']='relay-route-approved'
p.write_text(yaml.safe_dump(d,sort_keys=False))
VERSION
git -C repository add manifests
git -C repository commit -m 'Version the route while retaining the previous reader'
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
kubectl patch application station --type json -p '[{"op":"remove","path":"/spec/ignoreDifferences"}]'
kubectl annotate application station argocd.argoproj.io/refresh=hard --overwrite
kubectl patch application station --type merge --patch-file=patch-4cf3f622c706.json
for _ in $(seq 1 60); do
 if kubectl get application station -o json | jq -e --arg rev "$(cat release-commit)" '.status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null; then break; fi
 sleep 1
done
kubectl rollout status deployment/relay --timeout=60s
python3 -I - <<'PRESERVED'
import json,subprocess
from pathlib import Path
original=json.loads(Path('original-handover.json').read_text())
for kind,item in original.items():
 live=json.loads(subprocess.check_output(['kubectl','get',kind,item['name'],'-o','json']))
 assert live['metadata']['uid']==item['uid']
 if kind=='configmap':assert live['immutable'] and live['data']==item['data']
PRESERVED
test "$(kubectl exec retained-reader -- wget -qO- -T 3 http://127.0.0.1:8080)" = retained-54
