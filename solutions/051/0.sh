set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_RECOVER_PUBLICATION'
import json,subprocess
from pathlib import Path
facts=json.loads(Path('/run/dq/facts/0/progressive-identities.json').read_text());contract=facts['contract']
def cli(args,**kwargs):return subprocess.run(['kubectl',*args],check=True,text=True,capture_output=True,**kwargs)
name=contract['producer']['deployment'];deployment=json.loads(cli(['get','deployment',name,'-o','json']).stdout)
worker=next(c for c in deployment['spec']['template']['spec']['containers'] if c['name']=='worker')
worker['command']=['httpd','-f','-p','8080','-h','/srv/relay']
worker['volumeMounts']=[{'name':'source','mountPath':'/srv/relay','readOnly':True}]
worker['readinessProbe']['httpGet']['port']=8080
value={'spec':{'template':{'spec':{'containers':[worker],'volumes':[{'name':'source','configMap':{'name':contract['producer']['sourceConfigMap']}}]}}}}
cli(['patch','deployment',name,'--type=merge','-p',json.dumps(value)])
service={'apiVersion':'v1','kind':'Service','metadata':{'name':contract['publicService']['name']},'spec':{'type':'ClusterIP','selector':deployment['spec']['selector']['matchLabels'],'ports':[{'port':contract['publicService']['port'],'targetPort':8080}]}}
cli(['apply','-f','-'],input=json.dumps(service))
cli(['rollout','status','deployment/'+name,'--timeout=90s'])
DQ_RECOVER_PUBLICATION
for attempt in $(seq 1 60); do
 if kubectl exec deployment/relay -c worker -- wget -qO- -T 3 http://relay-gateway:8080/release.json | jq -e --arg id "$(jq -r .data.PRODUCER_ID /run/dq/facts/0/progressive-identities.json)" '.producer_id==$id and .route=="north"' >/dev/null; then break; fi
 sleep .5
done
kubectl exec deployment/relay -c worker -- wget -qO- -T 3 http://relay-gateway:8080/release.json | jq -e --arg id "$(jq -r .data.PRODUCER_ID /run/dq/facts/0/progressive-identities.json)" '.producer_id==$id and .route=="north"' >/dev/null
