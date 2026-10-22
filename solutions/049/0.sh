set -euo pipefail
cd ~/quest
source platform.env
python3 - <<'PIN'
import json,os
from pathlib import Path
p=Path('board.json');d=json.loads(p.read_text());d['spec']['template']['spec']['containers'][0]['image']=os.environ['PRIVATE_IMAGE'];p.write_text(json.dumps(d))
PIN
kubectl apply -f board.json
kubectl rollout status deployment/board --timeout=90s
