set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_RECOVER_FAILOVER'
import json,subprocess
from pathlib import Path
facts=json.loads(Path('/run/dq/facts/0/progressive-identities.json').read_text());contract=facts['contract']
def cli(args,**kwargs):return subprocess.run(['kubectl',*args],check=True,text=True,capture_output=True,**kwargs)
name=contract['consumer']['deployment'];deployment=json.loads(cli(['get','deployment',name,'-o','json']).stdout)
worker=next(c for c in deployment['spec']['template']['spec']['containers'] if c['name']=='worker')
source=contract['producer']['sourceConfigMap']
worker['env']=[{'name':key,'valueFrom':{'configMapKeyRef':{'name':source,'key':key}}} for key in contract['consumerEnvironment']]
worker['volumeMounts']=[{'name':'source','mountPath':'/source','readOnly':True}]
worker['command']=['sh','-c','mkdir -p /tmp/backup; cp /source/index.html /source/release.json /tmp/backup/; printf \'{"route":"%s","producer_id":"%s"}\\n\' "$ROUTE" "$PRODUCER_ID" > /tmp/backup/consumer.json; exec httpd -f -p 8080 -h /tmp/backup']
worker['readinessProbe']={'httpGet':{'path':contract['consumerPath'],'port':8080},'periodSeconds':1}
value={'spec':{'template':{'spec':{'containers':[worker],'volumes':[{'name':'source','configMap':{'name':source}}]}}}}
cli(['patch','deployment',name,'--type=merge','-p',json.dumps(value)])
cli(['rollout','status','deployment/'+name,'--timeout=90s'])
cli(['patch','service',contract['publicService']['name'],'--type=merge','-p',json.dumps({'spec':{'selector':deployment['spec']['selector']['matchLabels']}})])
DQ_RECOVER_FAILOVER
for attempt in $(seq 1 60); do
 if kubectl exec deployment/backup -c worker -- wget -qO- -T 3 http://relay-gateway:8080/consumer.json | jq -e --arg id "$(jq -r .data.PRODUCER_ID /run/dq/facts/0/progressive-identities.json)" '.producer_id==$id and .route=="north"' >/dev/null; then break; fi
 sleep .5
done
kubectl exec deployment/backup -c worker -- wget -qO- -T 3 http://relay-gateway:8080/consumer.json | jq -e --arg id "$(jq -r .data.PRODUCER_ID /run/dq/facts/0/progressive-identities.json)" '.producer_id==$id and .route=="north"' >/dev/null
