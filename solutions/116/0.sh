set -euo pipefail
cd ~/quest
kubectl patch stationboard station --type=json -p '[{"op": "replace", "path": "/spec/route", "value": "north-116"}]'
for i in $(seq 1 90); do
 if kubectl get stationboard station -o json | jq -e '.status.observedGeneration==.metadata.generation and .status.ready==true' >/dev/null && test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = north-116; then break; fi
 sleep 1
done
python3 -I - <<'DQ_CONSUMER_DELIVERY'
import json,subprocess,time
from pathlib import Path
contract=json.loads(Path('reconciliation-contract.json').read_text())
consumer=contract['consumer']
def cli(args,check=True):
    return subprocess.run(args,capture_output=True,text=True,check=check,timeout=100)
deployment=json.loads(cli(['kubectl','get','deployment',consumer['deployment'],'-o','json']).stdout)
selector=','.join(k+'='+v for k,v in deployment['spec']['selector']['matchLabels'].items())
before=json.loads(cli(['kubectl','get','pods','-l',selector,'-o','json']).stdout)['items']
cli(['kubectl','rollout','restart','deployment/'+consumer['deployment']])
cli(['kubectl','rollout','status','deployment/'+consumer['deployment'],'--timeout=90s'])
for pod in before:
    cli(['kubectl','wait','--for=delete','pod/'+pod['metadata']['name'],'--timeout=30s'])
deadline=time.monotonic()+30
while time.monotonic()<deadline:
    result=cli(['kubectl','exec','deployment/'+consumer['deployment'],'-c',consumer['container'],'--','wget','-qO-','-T','3','http://'+consumer['service']+':'+str(contract['interface']['port'])+contract['interface']['path']],False)
    if result.returncode==0 and result.stdout==contract['interface']['body']:break
    time.sleep(.5)
else:raise RuntimeError('Consumer publication did not converge')
DQ_CONSUMER_DELIVERY
