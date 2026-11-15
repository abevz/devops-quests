set -euo pipefail
cd ~/quest
cat > station.yaml <<'DQ_ASSET'
apiVersion: training.devops-quests.local/v1
kind: StationBoard
metadata:
  name: station
spec:
  route: closed
DQ_ASSET
python3 - station.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f station.yaml
cat > client.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client
spec:
  replicas: 1
  selector:
    matchLabels:
      app: client
  template:
    metadata:
      labels:
        app: client
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: worker
        image: __DQ_APP_IMAGE__
        imagePullPolicy: Never
        command:
        - sleep
        - '3600'
        resources:
          requests:
            cpu: 10m
            memory: 8Mi
          limits:
            cpu: 200m
            memory: 32Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
      terminationGracePeriodSeconds: 1
DQ_ASSET
python3 - client.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f client.yaml
kubectl rollout status deployment/client --timeout=90s

python3 -I - <<'DQ_RECONCILIATION_SEED'
import json,os,subprocess,time
from pathlib import Path
from dq_check import workload_worker
def cli(args):
    return subprocess.run(args,check=True,capture_output=True,text=True,timeout=100).stdout
def get(kind,name):
    return json.loads(cli(['kubectl','get',kind,name,'-o','json']))
def apply(value):
    subprocess.run(['kubectl','apply','-f','-'],input=json.dumps(value),text=True,check=True,timeout=30)
station=get('stationboard','station')
apply({'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'board-route','ownerReferences':[{'apiVersion':station['apiVersion'],'kind':'StationBoard','name':station['metadata']['name'],'uid':station['metadata']['uid'],'controller':True,'blockOwnerDeletion':False}]},'data':{'index.html':station['spec']['route']+'\n'}})
client=get('deployment','client');client['metadata']={'name':'client'};client.pop('status',None)
spec=client['spec']['template']['spec'];worker=workload_worker(client)
worker['command']=['httpd','-f','-p','8080','-h','/tmp/site']
worker['volumeMounts']=[{'name':'publication','mountPath':'/tmp/site/index.html','subPath':'index.html','readOnly':True}]
worker['readinessProbe']={'httpGet':{'path':'/','port':8080},'periodSeconds':1}
spec['volumes']=[{'name':'publication','configMap':{'name':'board-route'}}]
apply(client)
apply({'apiVersion':'v1','kind':'Service','metadata':{'name':'client-view'},'spec':{'selector':{'app':'client'},'ports':[{'port':8080,'targetPort':8080}]}})
cli(['kubectl','rollout','status','deployment/client','--timeout=90s'])
deadline=time.monotonic()+30
while time.monotonic()<deadline:
    response=subprocess.run(['kubectl','exec','deployment/client','-c','worker','--','wget','-qO-','-T','3','http://client-view:8080'],capture_output=True,text=True,timeout=10)
    if response.returncode==0 and response.stdout==station['spec']['route']+'\n':break
    time.sleep(.5)
else:raise RuntimeError('Bootstrap consumer publication is not ready')
contract={'apiVersion':'training.devops-quests.local/v1','kind':'StationBoard','station':'station','producer':{'deployment':'board','container':'board','configMap':'board-route','key':'index.html','service':'board'},'consumer':{'deployment':'client','container':'worker','service':'client-view','replicas':1},'interface':{'type':'ClusterIP','port':8080,'path':'/','body':'north-116\n'}}
identities={kind+'/'+name:get(kind,name)['metadata']['uid'] for kind,name in [('stationboard','station'),('configmap','board-route'),('deployment','client'),('service','client-view')]}
Path('reconciliation-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
Path('reconciliation-identities.json').write_text(json.dumps({'contract':contract,'identities':identities,'image':os.environ['DQ_APP_IMAGE']},indent=2)+'\n')
Path('client.yaml').unlink()
DQ_RECONCILIATION_SEED
