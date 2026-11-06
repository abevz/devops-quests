set -euo pipefail
cd ~/quest
python3 - defaults.yaml <<'DQ_YAML_FIX_126' > /tmp/fixed-defaults.yaml
import sys,yaml
from pathlib import Path
value=yaml.safe_load(Path(sys.argv[1]).read_text())
value["spec"]["limits"][0]["default"]["cpu"]="200m"
value["spec"]["limits"][0]["defaultRequest"]["cpu"]="100m"
sys.stdout.write(yaml.safe_dump(value, sort_keys=False))
DQ_YAML_FIX_126
cp /tmp/fixed-defaults.yaml defaults.yaml
kubectl apply -f defaults.yaml
# With the client and one board Pod, the quota has no room for a surge Pod.
kubectl scale deployment/board --replicas=0
settled=false
for attempt in $(seq 1 60); do
  pods=$(kubectl get pods -l app=board -o json)
  replicasets=$(kubectl get replicasets -l app=board -o json)
  if jq -e '.items | length==0' <<<"$pods" >/dev/null && jq -e 'all(.items[]; .spec.replicas==0)' <<<"$replicasets" >/dev/null; then
    settled=true
    break
  fi
  sleep 1
done
if ! "$settled"; then printf '%s\n' 'board Pods or ReplicaSets did not scale down within 60 seconds' >&2; exit 1; fi
kubectl rollout restart deployment/board
kubectl scale deployment/board --replicas=1
kubectl rollout status deployment/board --timeout=90s
