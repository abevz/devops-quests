set -euo pipefail
cd ~/quest
test "$(kubectl get deployment board -o jsonpath='{.metadata.uid}')" = "$(cat /run/dq/facts/0/original-deployment-uid)"
kubectl kustomize overlays/recovery > /tmp/rendered-overlay.yaml
name=$(python3 - <<'RENDER'
import yaml
items=list(yaml.safe_load_all(open('/tmp/rendered-overlay.yaml')))
cm=next(x for x in items if x['kind']=='ConfigMap');assert cm['data']=={'ROUTE':'north-108'}
assert cm['metadata']['name'].startswith('route-')
d=next(x for x in items if x['kind']=='Deployment');assert d['spec']['replicas']==2
print(cm['metadata']['name'])
RENDER
)
kubectl get deployment board -o json | jq -e --arg name "$name" '.spec.replicas==2 and .status.readyReplicas==2 and .spec.template.spec.containers[0].env==[{name:"ROUTE",valueFrom:{configMapKeyRef:{name:$name,key:"ROUTE"}}}]' >/dev/null
kubectl get configmap "$name" -o json | jq -e '.data=={ROUTE:"north-108"}' >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-108
