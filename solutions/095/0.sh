set -euo pipefail
cd ~/quest
source platform.env
git -C repository revert --no-edit "$(cat /run/dq/facts/0/faulty-commit)"
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" '.status.sync.revision==$rev and .status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null; then break; fi
 sleep 1
done
kubectl rollout status deployment/board --timeout=60s


source platform.env
python3 -I - <<'FORWARD'
from pathlib import Path
import yaml
body=Path('current-publication.json').read_text()
for lane in ['a','b']:
 p=Path('repository/readers')/lane/'resources.yaml';resources=list(yaml.safe_load_all(p.read_text()))
 for item in resources:
  if item['kind']=='ConfigMap':item['data']['index.html']=body
 p.write_text(yaml.safe_dump_all(resources,sort_keys=False))
FORWARD
git -C repository add readers
git -C repository commit -m 'Forward-port the current consumer publication during rollback'
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
for name in reader-a reader-b; do
 kubectl patch application "$name" --type merge -p "$(jq -n --arg revision "$(cat release-commit)" '{spec:{source:{targetRevision:$revision}}}')"
done
for name in board reader-a reader-b; do
 kubectl annotate application "$name" argocd.argoproj.io/refresh=hard --overwrite
 for _ in $(seq 1 90); do
  if kubectl get application "$name" -o json | jq -e --arg revision "$(cat release-commit)" '.status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$revision' >/dev/null; then break; fi
  sleep 1
 done
 kubectl rollout status "deployment/$name" --timeout=60s
done
for name in reader-a reader-b; do
 for _ in $(seq 1 90); do
  kubectl exec "deployment/$name" -c worker -- wget -qO- -T 3 "http://$name:8080" > observed-publication.json
  if cmp -s observed-publication.json current-publication.json; then break; fi
  sleep 1
 done
 cmp observed-publication.json current-publication.json
done
python3 -I - <<'PRESERVED'
import json,subprocess
from pathlib import Path
for key,uid in json.loads(Path('original-release-identities.json').read_text()).items():
 kind,name=key.split('/');live=json.loads(subprocess.check_output(['kubectl','get',kind,name,'-o','json']))
 assert live['metadata']['uid']==uid
PRESERVED
