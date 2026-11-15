set -euo pipefail
cd ~/quest
kubectl patch statefulset shelf --type=json -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["sh", "-c", "exec httpd -f -p 8080 -h /data"]}]'
kubectl rollout status statefulset/shelf --timeout=90s
python3 -I - <<'DQ_DISCOVERY_REFERENCE'
import copy,json,os,subprocess
from pathlib import Path
contract=json.loads(Path('discovery-contract.json').read_text())
source=json.loads(subprocess.check_output(['kubectl','get','statefulset','shelf','-o','json'],text=True))
spec=copy.deepcopy(source['spec']['template']['spec'])
spec.pop('volumes',None);spec.pop('initContainers',None);spec['automountServiceAccountToken']=False
worker=next(c for c in spec['containers'] if c['name']=='worker');worker.pop('volumeMounts',None)
hostname='shelf-0.'+source['spec']['serviceName']+'.'+os.environ['DQ_NAMESPACE']+'.svc.cluster.local'
worker['env']=[{'name':'UPSTREAM','value':'http://'+hostname+':8080'}]
worker['command']=['sh','-c','mkdir -p /tmp/site; httpd -p 8080 -h /tmp/site; while :; do if wget -qO /tmp/site/next -T 3 "$UPSTREAM"; then mv /tmp/site/next /tmp/site/index.html; else rm -f /tmp/site/next; fi; sleep 1; done']
value={'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':contract['consumer']},'spec':{'replicas':1,'selector':{'matchLabels':{'app':contract['consumer']}},'template':{'metadata':{'labels':{'app':contract['consumer']}},'spec':spec}}}
subprocess.run(['kubectl','apply','-f','-'],input=json.dumps(value),text=True,check=True)
subprocess.run(['kubectl','rollout','status','deployment/'+contract['consumer'],'--timeout=90s'],check=True)
DQ_DISCOVERY_REFERENCE
for attempt in $(seq 1 20); do
  result=$(kubectl exec deployment/inspector -c worker -- wget -qO- -T 3 http://127.0.0.1:8080 || true)
  if [ "$result" = ledger-111 ]; then exit 0; fi
  sleep 1
done
exit 1
