set -euo pipefail
cd ~/quest
source platform.env
python3 - <<'PIN'
import yaml,os
from pathlib import Path
p=Path('board.yaml');d=yaml.safe_load(p.read_text());d['spec']['template']['spec']['containers'][0]['image']=os.environ['PRIVATE_IMAGE'];p.write_text(yaml.safe_dump(d,sort_keys=False))
PIN
kubectl apply -f board.yaml
kubectl rollout status deployment/board --timeout=90s
