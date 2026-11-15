set -euo pipefail
cd ~/quest
kubectl patch service board --type=json -p '[{"op": "replace", "path": "/spec/ports/0/targetPort", "value": 8080}]'
url=$(jq -r .url /run/dq/facts/0/prometheus-target.json)
for i in $(seq 1 30); do
 if kubectl exec deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=up%7Bjob%3D%22board%22%7D" | jq -e '.data.result[0].value[1]=="1"' >/dev/null; then break; fi
 sleep 1
done
kubectl exec deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=up%7Bjob%3D%22board%22%7D" | jq -e '.data.result[0].value[1]=="1"' >/dev/null
python3 -I - <<'DQ_OBSERVER_REFERENCE'
from decimal import Decimal
import json,subprocess,time
from pathlib import Path
contract=json.loads(Path('observer-contract.json').read_text())
for consumer in contract['consumers']:
    subprocess.run(['kubectl','set','env','deployment/'+consumer['deployment'],
                    'METRIC=station_queue_depth','ROUTE=north'],check=True)
for consumer in contract['consumers']:
    subprocess.run(['kubectl','rollout','status','deployment/'+consumer['deployment'],'--timeout=90s'],check=True)
for consumer in contract['consumers']:
    deadline=time.monotonic()+30
    while True:
        response=subprocess.run(['kubectl','exec','deployment/'+consumer['deployment'],'--',
                                 'wget','-qO-','-T','2',contract['snapshotURL']],capture_output=True,text=True,timeout=5)
        try:
            body=json.loads(response.stdout);result=body['data']['result']
            valid=response.returncode==0 and body.get('status')=='success' and len(result)==1 and Decimal(result[0]['value'][1])==consumer['expected']
        except (ValueError,KeyError,TypeError,IndexError):valid=False
        if valid:break
        if time.monotonic()>=deadline:raise RuntimeError('Observer query has not converged')
        time.sleep(1)
DQ_OBSERVER_REFERENCE
