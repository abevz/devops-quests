set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_ADMISSION_REFERENCE'
import json,subprocess
from pathlib import Path
contract=json.loads(Path('admission-contract.json').read_text())
value=json.loads(subprocess.check_output(['kubectl','get','limitrange',contract['defaults'],'-o','json'],text=True))
value['metadata']={'name':contract['defaults']}
value.pop('status',None)
for item in value['spec']['limits']:
    if item['type']=='Container':
        item['default']=contract['admitted']['limits']
        item['defaultRequest']=contract['admitted']['requests']
subprocess.run(['kubectl','apply','-f','-'],input=json.dumps(value),text=True,check=True)
for name in contract['workloads']:
    current=json.loads(subprocess.check_output(['kubectl','get','deployment',name,'-o','json'],text=True))
    worker=next(i for i,c in enumerate(current['spec']['template']['spec']['containers']) if c['name']=='worker')
    patch=[{'op':'replace','path':'/spec/template/spec/containers/'+str(worker)+'/resources','value':{}}]
    subprocess.run(['kubectl','patch','deployment',name,'--type=json','-p',json.dumps(patch)],check=True)
DQ_ADMISSION_REFERENCE
kubectl scale deployment/client deployment/board --replicas=0
settled=false
for attempt in $(seq 1 60); do
  pods=$(kubectl get pods -o json)
  sets=$(kubectl get replicasets -o json)
  if jq -e '[.items[] | select(.metadata.labels.app=="client" or .metadata.labels.app=="board")]|length==0' <<<"$pods" >/dev/null &&
     jq -e '[.items[] | select(.metadata.labels.app=="client" or .metadata.labels.app=="board")] | all(.[]; .spec.replicas==0)' <<<"$sets" >/dev/null; then
    settled=true
    break
  fi
  sleep 1
done
if ! "$settled"; then printf '%s\n' 'Supplied consumers did not quiesce within60seconds' >&2; exit 1; fi
kubectl scale deployment/client --replicas=1
kubectl rollout status deployment/client --timeout=90s
kubectl scale deployment/board --replicas=1
kubectl rollout status deployment/board --timeout=90s
