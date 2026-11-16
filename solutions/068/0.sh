set -euo pipefail
cd ~/quest

source platform.env
kubectl create configmap board-publication --from-file=publication/index.html --from-file=publication/contract.json --dry-run=client -o yaml > repository/manifests/publication.yaml
python3 -I - <<'DELIVERY'
from pathlib import Path
import yaml
p=Path('repository/manifests/board.yaml')
document=yaml.safe_load(p.read_text());pod=document['spec']['template']['spec'];worker=pod['containers'][0]
worker['command']=['httpd','-f','-p','8080','-h','/publication']
worker['readinessProbe']['httpGet']={'path':'/contract.json','port':8080}
worker['volumeMounts']=[{'name':'publication','mountPath':'/publication','readOnly':True}]
pod['volumes']=[{'name':'publication','configMap':{'name':'board-publication','defaultMode':0o444}}]
p.write_text(yaml.safe_dump(document,sort_keys=False))
DELIVERY
git -C repository add manifests
git -C repository commit -m 'Deliver the consumer health publication'
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for _ in $(seq 1 90); do
 if kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" '.status.sync.revision==$rev and .status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null; then break; fi
 sleep 1
done
kubectl rollout status deployment/board --timeout=60s
test "$(kubectl get deployment board -o jsonpath='{.metadata.uid}')" = "$(cat original-deployment-uid)"
kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080/contract.json > observed-contract.json
cmp observed-contract.json publication/contract.json
kubectl get configmap board-publication -o json | jq -e --rawfile index publication/index.html --rawfile contract publication/contract.json '.data=={"index.html":$index,"contract.json":$contract}' >/dev/null
