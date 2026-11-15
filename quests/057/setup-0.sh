set -euo pipefail
cat > spool.yaml <<'DQ_ASSET'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: spool
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: unknown-rail
  resources:
    requests:
      storage: 8Mi
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' spool.yaml
kubectl apply -f spool.yaml
cat > deployment.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: relay
spec:
  replicas: 1
  selector:
    matchLabels:
      app: relay
  template:
    metadata:
      labels:
        app: relay
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: worker
        image: ${DQ_APP_IMAGE}
        imagePullPolicy: Never
        command:
        - sh
        - -c
        - mkdir -p /tmp/www; echo signalrail >/tmp/www/index.html; httpd -f -p 8080 -h /tmp/www
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            memory: 64Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: spool
          mountPath: /spool
      volumes:
      - name: spool
        persistentVolumeClaim:
          claimName: spool
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' deployment.yaml
kubectl apply -f deployment.yaml

python3 -I - <<'DQ_STORAGE_SEED'
import copy,hashlib,json,os,secrets,subprocess
from pathlib import Path
from dq_check import workload_worker
def cli(args):
    return subprocess.run(args,capture_output=True,text=True,check=True,timeout=100).stdout
def get(kind,name):
    return json.loads(cli(['kubectl','get',kind] + ([name] if name else []) + ['-o','json']))
def apply(obj):
    subprocess.run(['kubectl','apply','-f','-'],input=json.dumps(obj),text=True,check=True,timeout=30)
relay=get('deployment','relay')
apply({'apiVersion':'v1','kind':'PersistentVolumeClaim','metadata':{'name':'reserve'},'spec':{'accessModes':['ReadWriteOnce'],'storageClassName':'standard','resources':{'requests':{'storage':'8Mi'}}}})
source=copy.deepcopy(relay);source['metadata']={'name':'reserve'};source.pop('status',None);source['spec']['revisionHistoryLimit']=0;source['spec']['selector']['matchLabels']={'app':'reserve'};source['spec']['template']['metadata']['labels']={'app':'reserve'}
spec=source['spec']['template']['spec'];spec['securityContext']['fsGroup']=1000;spec['securityContext']['runAsGroup']=1000;spec['terminationGracePeriodSeconds']=1;spec['volumes']=[{'name':'archive','persistentVolumeClaim':{'claimName':'reserve'}}];worker=workload_worker(source);worker['command']=['httpd','-f','-p','8080','-h','/archive'];worker['volumeMounts']=[{'name':'archive','mountPath':'/archive','readOnly':True}]
publication='restore-'+secrets.token_hex(16)
spec['initContainers']=[{'name':'seed','image':worker['image'],'imagePullPolicy':'Never','command':['sh','-c','dd if=/dev/zero of=/archive/payload.bin bs=1024 count=64 2>/dev/null; printf "%s\\n" "$PUBLICATION" > /archive/index.html'],'env':[{'name':'PUBLICATION','value':publication}],'securityContext':copy.deepcopy(worker['securityContext']),'resources':{'requests':{'cpu':'10m','memory':'8Mi'},'limits':{'cpu':'100m','memory':'16Mi'}},'volumeMounts':[{'name':'archive','mountPath':'/archive'}]}]
apply(source);cli(['kubectl','rollout','status','deployment/reserve','--timeout=90s'])
before=json.loads(cli(['kubectl','get','pods','-l','app=reserve','-o','json']))['items']
source=get('deployment','reserve');source['metadata']={'name':'reserve'};source.pop('status',None);source['spec']['template']['spec'].pop('initContainers')
apply(source);cli(['kubectl','rollout','status','deployment/reserve','--timeout=90s'])
for pod in before:
    cli(['kubectl','wait','--for=delete','pod/'+pod['metadata']['name'],'--timeout=30s'])
actual=cli(['kubectl','exec','deployment/reserve','-c','worker','--','cat','/archive/index.html'])
if actual != publication+'\n':raise RuntimeError('Source publication is not initialized')
expected=hashlib.sha256(bytes(65536)).hexdigest()
if cli(['kubectl','exec','deployment/reserve','-c','worker','--','sha256sum','/archive/payload.bin']).split()[0] != expected:raise RuntimeError('Source payload is not initialized')
relay['metadata']={'name':'relay'};relay.pop('status',None);spec=relay['spec']['template']['spec'];spec['securityContext']['fsGroup']=1000;spec['securityContext']['runAsGroup']=1000;spec['terminationGracePeriodSeconds']=1;workload_worker(relay)['command']=['httpd','-f','-p','8080','-h','/spool'];apply(relay)
contract={'source':{'claim':'reserve','deployment':'reserve','container':'worker','mountPath':'/archive','replicas':1},'target':{'claim':'spool','deployment':'relay','container':'worker','mountPath':'/spool','replicas':1},'dataset':[{'path':'index.html','type':'regular','bytes':len(actual.encode()),'sha256':hashlib.sha256(actual.encode()).hexdigest()},{'path':'payload.bin','type':'regular','bytes':65536,'sha256':expected}],'interface':{'port':8080,'path':'/','body':actual}}
identities={kind+'/'+name:get(kind,name)['metadata']['uid'] for kind,name in [('deployment','relay'),('deployment','reserve'),('pvc','reserve')]}
Path('storage-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
Path('storage-identities.json').write_text(json.dumps({'contract':contract,'identities':identities,'image':os.environ['DQ_APP_IMAGE']},indent=2)+'\n')
for name in ('spool.yaml','deployment.yaml'):Path(name).unlink()
DQ_STORAGE_SEED
