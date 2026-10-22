set -euo pipefail
cd ~/quest
python3 - <<'TARGET'
from pathlib import Path
import yaml
p=Path('overlays/recovery/kustomization.yaml');d=yaml.safe_load(p.read_text());d['patches'][0]['target']['name']='board';p.write_text(yaml.safe_dump(d,sort_keys=False))
TARGET
kubectl kustomize overlays/recovery
kubectl apply -k overlays/recovery
kubectl rollout status deployment/board --timeout=60s
