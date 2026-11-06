set -euo pipefail
cd ~/quest
source platform.env
python3 - <<'PIN'
import json,yaml
from pathlib import Path
p=Path('repository/manifests/board.yaml');d=yaml.safe_load(p.read_text());d['spec']['template']['spec']['containers'][0]['image']=json.loads(Path('/run/dq/facts/0/private-release.json').read_text())['image'];p.write_text(yaml.safe_dump(d,sort_keys=False))
PIN
cd repository
git add manifests/board.yaml
git commit -m 'Pin recovered private board release'
git push origin main
git rev-parse HEAD > ../release-commit
cd ..
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if kubectl get application board -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null && kubectl rollout status deployment/board --timeout=2s >/dev/null 2>&1; then break; fi
 sleep 1
done
