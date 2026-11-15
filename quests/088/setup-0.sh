set -euo pipefail
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
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: worker
        image: ${DQ_APP_IMAGE}
        imagePullPolicy: Never
        command:
        - sh
        - -c
        - x=xxxxxxxx; while :; do x=$x$x; done
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: 16Mi
          limits:
            memory: 16Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        readinessProbe:
          httpGet:
            port: 9090
            path: /
          periodSeconds: 2
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' deployment.yaml
kubectl apply -f deployment.yaml

python3 -I - <<'DQ_STARTUP_SEED'
import copy,hashlib,json,secrets,subprocess
from pathlib import Path
from dq_check import workload_worker

def command(args):
    return subprocess.run(args,capture_output=True,text=True,check=True,timeout=90).stdout

def get(kind,name):
    return json.loads(command(['kubectl','get',kind,name,'-o','json']))

def apply(value):
    subprocess.run(['kubectl','apply','-f','-'],input=json.dumps(value),capture_output=True,text=True,check=True,timeout=60)

producer=get('deployment','relay')
image=workload_worker(producer)['image']
cache_id=secrets.token_hex(16)
policy={'CACHE_MIB':'80','CACHE_ID':cache_id}
digest=hashlib.sha256()
block=bytes(1024*1024)
for _ in range(80):digest.update(block)
expected={'cache_id':cache_id,'bytes':80*1024*1024,'sha256':digest.hexdigest()}
apply({'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'startup-source'},'data':policy})
warmer='set -eu\nmkdir -p /cache\ndd if=/dev/zero of=/cache/payload bs=1048576 count="$CACHE_MIB"\nbytes=$(stat -c %s /cache/payload)\ndigest=$(sha256sum /cache/payload); digest=${digest%% *}\nprintf \'{"cache_id":"%s","bytes":%s,"sha256":"%s"}\\n\' "$CACHE_ID" "$bytes" "$digest" > /cache/record.json\nprintf \'signalrail\\n\' > /cache/index.html\n'
volume=[{'name':'cache','emptyDir':{'medium':'Memory'}}]
mount=[{'name':'cache','mountPath':'/cache'}]
source_env=[{'name':key,'valueFrom':{'configMapKeyRef':{'name':'startup-source','key':key}}} for key in ['CACHE_MIB','CACHE_ID']]
for name in ['relay','stager','reader']:
    apply({'apiVersion':'v1','kind':'Service','metadata':{'name':name},'spec':{'selector':{'app':name},'ports':[{'port':8080,'targetPort':8080}]}})
    if name=='relay':continue
    consumer={'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':name},'spec':copy.deepcopy(producer['spec'])}
    consumer['spec']['selector']['matchLabels']={'app':name}
    consumer['spec']['template']['metadata']['labels']={'app':name}
    spec=consumer['spec']['template']['spec']
    spec['terminationGracePeriodSeconds']=1
    spec['volumes']=copy.deepcopy(volume)
    worker=spec['containers'][0]
    worker['resources']={'requests':{'cpu':'10m','memory':'16Mi'},'limits':{'memory':'96Mi'}}
    worker['volumeMounts']=copy.deepcopy(mount)
    worker['readinessProbe']={'httpGet':{'path':'/record.json','port':8080},'periodSeconds':1}
    if name=='stager':
        init=copy.deepcopy(worker)
        init['name']='warmer'
        init.pop('readinessProbe')
        init['env']=copy.deepcopy(source_env)
        init['command']=['sh','-c',warmer]
        init['resources']['limits']['memory']='32Mi'
        spec['initContainers']=[init]
        worker['command']=['httpd','-f','-p','8080','-h','/cache']
    else:
        worker['env']=[{'name':'CACHE_MIB','value':'112'},{'name':'CACHE_ID','value':cache_id}]
        worker['command']=['sh','-c',warmer+'exec httpd -f -p 8080 -h /cache']
    apply(consumer)
contract={'producer':'relay','roles':[{'deployment':'relay','service':'relay'},{'deployment':'stager','service':'stager','initializer':'warmer'},{'deployment':'reader','service':'reader'}],'sourceConfigMap':'startup-source','memory':{'podCeiling':'96Mi','producerWorkerLimit':'96Mi'},'dataset':{'bytes':expected['bytes'],'byte':0,'sha256':expected['sha256']},'cacheLifetime':'Pod','payloadPath':'/cache/payload','memoryPath':'/cache','filesystem':'tmpfs','metadataPath':'/record.json','servicePort':8080,'serviceType':'ClusterIP','metadataSchema':{'cache_id':'string','bytes':'integer','sha256':'string'}}
identities={kind+'/'+name:get(kind,name)['metadata']['uid'] for kind,name in [('deployment','relay'),('service','relay'),('configmap','startup-source'),('deployment','stager'),('service','stager'),('deployment','reader'),('service','reader')]}
facts={'contract':contract,'identities':identities,'image':image,'policy':policy,'publication':expected}
Path('startup-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
Path('startup-identities.json').write_text(json.dumps(facts,indent=2)+'\n')
DQ_STARTUP_SEED
rm deployment.yaml
