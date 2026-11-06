set -euo pipefail
cd ~/quest
python3 - <<'REPAIR_YAML'
from pathlib import Path
import yaml
p=Path('repository/apps/child.yaml'); d=yaml.safe_load(p.read_text()); d['spec']['source']['path']='manifests'; p.write_text(yaml.safe_dump(d,sort_keys=False))
REPAIR_YAML
git -C repository add apps/child.yaml
git -C repository commit -m 'Restore child source path'
git -C repository push origin main
kubectl annotate application parent argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if bash wait-apps.sh; then break; fi
 sleep 1
done
bash wait-apps.sh
