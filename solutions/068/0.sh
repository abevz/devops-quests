set -euo pipefail
cd ~/quest
source platform.env
python3 - <<'PROBE'
import json
from pathlib import Path
p=Path('repository/manifests/board.json');d=json.loads(p.read_text());d['spec']['template']['spec']['containers'][0]['readinessProbe']['httpGet']['port']=8080;p.write_text(json.dumps(d,indent=2))
PROBE
cd repository
git add manifests/board.json
git commit -m 'Correct board readiness port'
git push origin main
git rev-parse HEAD > ../release-commit
cd ..
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if kubectl get application board -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null && kubectl rollout status deployment/board --timeout=2s >/dev/null 2>&1; then break; fi
 sleep 1
done
