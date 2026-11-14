set -euo pipefail
cd ~/quest
python3 - <<'CANDIDATE'
import yaml
from pathlib import Path
p=Path('green.yaml');v=yaml.safe_load(p.read_text());v['spec']['template']['spec']['containers'][0]['command'][-1]=v['spec']['template']['spec']['containers'][0]['command'][-1].replace('-p 8099', '-p 8080');p.write_text(yaml.safe_dump(v,sort_keys=False))
CANDIDATE
kubectl apply -f green.yaml
kubectl rollout status deployment/green --timeout=90s
kubectl patch service board --type=json -p '[{"op": "replace", "path": "/spec/selector", "value": {"app": "green"}}]'
for i in $(seq 1 20); do
 if test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = green-115; then break; fi
 sleep 1
done
# Rollout readiness can precede removal of terminating Pod IPs.
for i in $(seq 1 60); do
 if kubectl get pods -l 'app in (blue,green)' -o json | jq -e 'all(.items[]; .metadata.deletionTimestamp==null)' >/dev/null; then break; fi
 sleep 1
done
kubectl get pods -l 'app in (blue,green)' -o json | jq -e 'all(.items[]; .metadata.deletionTimestamp==null)' >/dev/null
