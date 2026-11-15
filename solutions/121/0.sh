set -euo pipefail
cd ~/quest
printf '%s
' '{"action":"restore-path"}' > webhook-repair.json
for i in $(seq 1 30); do
 if kubectl get validatingwebhookconfiguration "dq-webhook-${DQ_NAMESPACE#dq-}" -o json | jq -e '.webhooks[0].clientConfig.url|endswith("/validate")' >/dev/null; then break; fi
 sleep 1
done
python3 - route.yaml <<'DQ_YAML_FIX_121' > /tmp/fixed-route.yaml
import sys,yaml
from pathlib import Path
value=yaml.safe_load(Path(sys.argv[1]).read_text())
value["data"]["route"]="north-121"
sys.stdout.write(yaml.safe_dump(value, sort_keys=False))
DQ_YAML_FIX_121
cp /tmp/fixed-route.yaml route.yaml
kubectl apply -f route.yaml
kubectl rollout status deployment/board --timeout=90s

python3 -I - <<'DQ_ADOPT_REFERENCE'
import json,subprocess
for name in ['route-env','route-file']:
 obj=json.loads(subprocess.check_output(['kubectl','get','deployment',name,'-o','json'],text=True))
 spec=obj['spec']['template']['spec'];worker=next(c for c in spec['containers'] if c['name']=='worker')
 if name=='route-env':
  next(e for e in worker['env'] if e['name']=='ROUTE')['valueFrom']['configMapKeyRef']={'name':'route','key':'route'}
 else:
  next(v for v in spec['volumes'] if v['name']=='input')['configMap']['name']='route'
 subprocess.run(['kubectl','apply','-f','-'],input=json.dumps(obj),text=True,check=True)
 subprocess.run(['kubectl','rollout','status','deployment/'+name,'--timeout=90s'],check=True)
DQ_ADOPT_REFERENCE
