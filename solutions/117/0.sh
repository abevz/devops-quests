set -euo pipefail
cd ~/quest
python3 - <<'STATIC_FIX'
import yaml
from pathlib import Path
p=Path('static-pod.yaml');value=yaml.safe_load(p.read_text());value['spec']['containers'][0]['command'][-1]=value['spec']['containers'][0]['command'][-1].replace('-p 8099','-p 8080');p.write_text(yaml.safe_dump(value, sort_keys=False))
STATIC_FIX
for i in $(seq 1 90); do
 if test -s /run/dq/observations/static-pod.json && test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = north-117; then break; fi
 sleep 1
done
