set -euo pipefail
cd ~/quest
python3 - <<'REPAIR_YAML'
from pathlib import Path
import yaml
p=Path('applicationset.yaml'); d=yaml.safe_load(p.read_text()); d['spec']['template']['spec']['source']['path']='stations/{{.station}}'; p.write_text(yaml.safe_dump(d,sort_keys=False))
REPAIR_YAML
for i in $(seq 1 90); do
 if bash wait-apps.sh; then break; fi
 sleep 1
done
bash wait-apps.sh
