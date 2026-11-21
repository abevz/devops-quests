set -euo pipefail
cd ~/quest
python3 - <<'DQ_READY'
from pathlib import Path
import yaml

path = Path('board.yaml')
board = yaml.safe_load(path.read_text())
worker = next(c for c in board['spec']['template']['spec']['containers'] if c['name'] == 'worker')
worker['command'][-1] = worker['command'][-1].replace('"retired"', '"north-40"').replace(
    '; exec httpd', '; printf "%s\\n" "ready" > /tmp/site/ready; exec httpd'
)
worker['readinessProbe']['httpGet']['path'] = '/ready'
path.write_text(yaml.safe_dump(board, sort_keys=False))
DQ_READY
kubectl apply -f board.yaml
kubectl rollout status deployment/board --timeout=90s
retiring_pod_names=$(kubectl get pods -l app=board -o json | jq -r '.items[] | select(.metadata.deletionTimestamp!=null) | "pod/"+.metadata.name')
if test -n "$retiring_pod_names"; then
 mapfile -t retiring_pods <<< "$retiring_pod_names"
 kubectl wait --for=delete "${retiring_pods[@]}" --timeout=60s
fi
kubectl wait --for='jsonpath={.status.availableReplicas}=2' deployment/board --timeout=45s
