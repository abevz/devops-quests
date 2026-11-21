set -euo pipefail
cd ~/quest
python3 - <<'REPAIR_YAML'
from pathlib import Path
import yaml

child_path = Path('repository/apps/child.yaml')
child = yaml.safe_load(child_path.read_text())
child['spec']['source']['path'] = 'manifests'
child_path.write_text(yaml.safe_dump(child, sort_keys=False))

workload_path = Path('repository/manifests/board.yaml')
board = yaml.safe_load(workload_path.read_text())
volumes = board['spec']['template']['spec']['volumes']
next(volume for volume in volumes if volume['name'] == 'publication')['configMap']['name'] = 'board-publication'
workload_path.write_text(yaml.safe_dump(board, sort_keys=False))
REPAIR_YAML
git -C repository add apps/child.yaml manifests/board.yaml
git -C repository commit -m 'Restore child source and approved publication'
git -C repository push origin main
kubectl annotate application parent argocd.argoproj.io/refresh=hard --overwrite
approved=$(cat approved-publication)
publication_ready() {
  test "$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080/publication/revision 2>/dev/null)" = "$approved"
}
for i in $(seq 1 90); do
  if bash wait-apps.sh && publication_ready; then
    exit 0
  fi
  sleep 1
done
bash wait-apps.sh
publication_ready
