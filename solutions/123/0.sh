set -euo pipefail
cd ~/quest
python3 - <<'REPAIR_YAML'
from pathlib import Path
import yaml

path = Path('applicationset.yaml')
appset = yaml.safe_load(path.read_text())
source = appset['spec']['template']['spec']['source']
source['path'] = 'stations/{{.station}}'
source['targetRevision'] = Path('release-ref').read_text().strip()
path.write_text(yaml.safe_dump(appset, sort_keys=False))
REPAIR_YAML
for i in $(seq 1 90); do
 if bash wait-apps.sh; then break; fi
 sleep 1
done
bash wait-apps.sh
