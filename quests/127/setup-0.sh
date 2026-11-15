set -euo pipefail
cd ~/quest
cat > metrics.yaml <<'DQ_ASSET'
apiVersion: v1
kind: ConfigMap
metadata:
  name: board-metrics
data:
  metrics.txt: '# TYPE station_queue_depth gauge

    station_queue_depth{route="north",platform="a"} 3

    station_queue_depth{route="north",platform="b"} 4

    station_queue_depth{route="south",platform="a"} 9

    '
DQ_ASSET
python3 - metrics.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f metrics.yaml
cat > board.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: board
spec:
  replicas: 1
  selector:
    matchLabels:
      app: board
  template:
    metadata:
      labels:
        app: board
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
        - httpd
        - -f
        - -p
        - '8080'
        - -h
        - /site
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
        volumeMounts:
        - name: metrics
          mountPath: /site
          readOnly: true
      volumes:
      - name: metrics
        configMap:
          name: board-metrics
DQ_ASSET
python3 - board.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f board.yaml
cat > service.yaml <<'DQ_ASSET'
apiVersion: v1
kind: Service
metadata:
  name: board
spec:
  selector:
    app: board
  ports:
  - name: http
    port: 8080
    targetPort: 8099
DQ_ASSET
python3 - service.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f service.yaml
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
kubectl rollout status deployment/board --timeout=90s
kubectl rollout status deployment/client --timeout=90s
python3 -I - <<'DQ_OBSERVER_SEED'
import copy,hashlib,json,subprocess
from pathlib import Path
def get(kind,name):
    return json.loads(subprocess.check_output(['kubectl','get',kind,name,'-o','json'],text=True))
def create(value):
    subprocess.run(['kubectl','create','-f','-'],input=json.dumps(value),text=True,check=True)
program='set -eu\ncase "$OPERATION" in count|sum) ;; *) exit 1 ;; esac\nfor value in "$METRIC" "$JOB" "$ROUTE"; do\n case "$value" in \'\'|*[!A-Za-z0-9_:]*) exit 1 ;; esac\ndone\nmkdir -p /tmp/status\nprintf \'%s\\n\' \'{"status":"error","data":{"result":[]}}\' > /tmp/status/index.html\nprintf \'%s\\n\' 0 > /tmp/observations\nhttpd -f -p 8080 -h /tmp/status &\nhttp_pid=$!\ntrap \'kill "$http_pid" 2>/dev/null || true; exit\' INT TERM\nquery="$PROMETHEUS_URL/api/v1/query?query=$OPERATION%28$METRIC%7Bjob%3D%22$JOB%22%2Croute%3D%22$ROUTE%22%7D%29"\ncount=0\nwhile :; do\n if wget -qO /tmp/status/next -T 2 "$query"; then\n  mv /tmp/status/next /tmp/status/index.html\n  count=$((count+1))\n  printf \'%s\\n\' "$count" > /tmp/observations.next\n  mv /tmp/observations.next /tmp/observations\n fi\n sleep 1\ndone\n'
endpoint=json.loads(Path('prometheus-target.json').read_text())['url']
original=get('deployment','client')
create({'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'observer-program'},'data':{'poll.sh':program}})
consumers=[]
for name,operation,expected in [('observer-count','count',2),('observer-total','sum',7)]:
    value=copy.deepcopy(original)
    value['metadata']={'name':name};value.pop('status',None)
    value['spec']['selector']={'matchLabels':{'app':name}}
    value['spec']['template']['metadata']={'labels':{'app':name}}
    policy=value['spec']['template']['spec']
    policy['automountServiceAccountToken']=False
    policy['volumes']=[{'name':'program','configMap':{'name':'observer-program'}}]
    worker=policy['containers'][0]
    worker['command']=['sh','/opt/observer/poll.sh']
    worker['env']=[{'name':key,'value':text} for key,text in {
        'PROMETHEUS_URL':endpoint,'METRIC':'station_queue_old','ROUTE':'retired',
        'JOB':'board','OPERATION':operation}.items()]
    worker['volumeMounts']=[{'name':'program','mountPath':'/opt/observer','readOnly':True}]
    worker['readinessProbe']={'httpGet':{'path':'/','port':8080},'periodSeconds':1,'failureThreshold':3}
    create(value)
    subprocess.run(['kubectl','rollout','status','deployment/'+name,'--timeout=90s'],check=True)
    consumers.append({'deployment':name,'operation':operation,'expected':expected})
contract={'schema':1,'consumers':consumers,'programConfigMap':'observer-program','programKey':'poll.sh',
          'programPath':'/opt/observer/poll.sh','counterPath':'/tmp/observations',
          'snapshotURL':'http://127.0.0.1:8080','environmentInputs':['PROMETHEUS_URL','METRIC','ROUTE','JOB','OPERATION'],
          'preserveProvidedPollingCode':True,'preserveExistingWorkloadsAndService':True,
          'preserveProvidedWorkerImages':True,'oneCurrentReadyPodPerConsumer':True,
          'currentDesiredAndRunningInputs':True,'publishLiveQueryResult':True,
          'observationProgress':True,'observesCurrentStateOnly':True}
deployments={}
for name in ['board','client']+[item['deployment'] for item in consumers]:
    value=get('deployment',name)
    deployments[name]={'uid':value['metadata']['uid'],
                       'image':next(item['image'] for item in value['spec']['template']['spec']['containers'] if item['name']=='worker')}
facts={'contract':contract,'deployments':deployments,'serviceUID':get('service','board')['metadata']['uid'],
       'metricsUID':get('configmap','board-metrics')['metadata']['uid'],
       'programUID':get('configmap','observer-program')['metadata']['uid'],
       'programHash':hashlib.sha256(program.encode()).hexdigest(),
       'intent':{'PROMETHEUS_URL':endpoint,'METRIC':'station_queue_depth','ROUTE':'north','JOB':'board'}}
Path('observer-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
Path('observer-identities.json').write_text(json.dumps(facts)+'\n')
DQ_OBSERVER_SEED
rm -f metrics.yaml board.yaml service.yaml client.yaml
