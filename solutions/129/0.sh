set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_RETIREMENT_REFERENCE'
import json,subprocess
retired=json.loads(subprocess.check_output(['kubectl','get','secret','station-record','-o','json'],text=True))
successor={'apiVersion':'v1','kind':'Secret','metadata':{'name':'station-successor'},
           'type':retired.get('type','Opaque'),'data':retired['data']}
subprocess.run(['kubectl','apply','-f','-'],input=json.dumps(successor),text=True,check=True)
for name in ('dispatch','reporter'):
    patch={'spec':{'template':{'spec':{'volumes':[{'name':'configuration','secret':{'secretName':'station-successor'}}]}}}}
    subprocess.run(['kubectl','patch','deployment',name,'--type=strategic','-p',json.dumps(patch)],check=True)
for name in ('dispatch','reporter'):
    subprocess.run(['kubectl','rollout','status','deployment/'+name,'--timeout=90s'],check=True)
DQ_RETIREMENT_REFERENCE
set -euo pipefail
cd ~/quest
kubectl get configmap station -o json > /tmp/parent-live.json
kubectl get secret station-record -o json > /tmp/child-live.json
python3 - <<'CLEANUP_PROOF'
import json
from pathlib import Path
c=json.loads(Path('/run/dq/facts/0/cleanup-contract.json').read_text());p=json.loads(Path('/tmp/parent-live.json').read_text());child=json.loads(Path('/tmp/child-live.json').read_text())
assert p['metadata']['uid']==c['parent_uid'] and p['metadata']['deletionTimestamp']
assert child['metadata']['uid']==c['child_uid'] and child['metadata']['labels']['training.devops-quests.local/parent-uid']==c['parent_uid']
Path('/tmp/delete-child.json').write_text(json.dumps({'apiVersion':'v1','kind':'DeleteOptions','preconditions':{'uid':c['child_uid']}}))
Path('/tmp/release-finalizer.json').write_text(json.dumps([{'op':'test','path':'/metadata/uid','value':c['parent_uid']},{'op':'test','path':'/metadata/finalizers','value':['training.devops-quests.local/cleanup']},{'op':'remove','path':'/metadata/finalizers'}]))
CLEANUP_PROOF
kubectl delete --raw="/api/v1/namespaces/$DQ_NAMESPACE/secrets/station-record" -f /tmp/delete-child.json
kubectl patch configmap station --type=json --patch-file /tmp/release-finalizer.json
