set -euo pipefail
cd ~/quest
python3 - <<'POLICY'
import yaml
from pathlib import Path
p=Path('repository/policies/budget.yaml');policy=yaml.safe_load(p.read_text());policy['spec']['minAvailable']=1;p.write_text(yaml.safe_dump(policy,sort_keys=False))
POLICY
git -C repository add policies/budget.yaml
git -C repository commit -m 'Allow protected maintenance'
git -C repository push origin main
kubectl annotate application maintenance argocd.argoproj.io/refresh=hard --overwrite
kubectl patch pdb companion --type=merge -p '{"spec":{"selector":{"matchExpressions":null,"matchLabels":{"app":"companion"}}}}'
for i in $(seq 1 90); do
 if kubectl get application maintenance -o json | jq -e --arg rev "$(git -C repository rev-parse HEAD)" '.status.sync.status=="Synced" and .status.sync.revision==$rev' >/dev/null && kubectl get pdb -o json | jq -e 'all(.items[];.status.currentHealthy==2 and .status.disruptionsAllowed==1)' >/dev/null; then break; fi
 sleep 1
done
printf '[]\n' > evictions.json
for pool in relay companion; do
 pod=$(kubectl get pods -l "app=$pool" -o jsonpath='{.items[0].metadata.name}')
 uid=$(kubectl get pod "$pod" -o jsonpath='{.metadata.uid}')
 jq -n --arg pod "$pod" --arg ns "$DQ_NAMESPACE" --arg uid "$uid" '{apiVersion:"policy/v1",kind:"Eviction",metadata:{name:$pod,namespace:$ns},deleteOptions:{preconditions:{uid:$uid}}}' > /tmp/eviction.json
 jq --slurpfile next /tmp/eviction.json '.+[$next[0]]' evictions.json > /tmp/requests.json
 cp /tmp/requests.json evictions.json
 kubectl create --raw "/api/v1/namespaces/$DQ_NAMESPACE/pods/$pod/eviction" -f /tmp/eviction.json
 kubectl wait --for=delete "pod/$pod" --timeout=60s
 kubectl rollout status "deployment/$pool" --timeout=90s
done
for i in $(seq 1 30); do
 if kubectl get pdb -o json | jq -e 'all(.items[];.status.currentHealthy==2 and .status.disruptionsAllowed==1)' >/dev/null; then break; fi
 sleep 1
done
