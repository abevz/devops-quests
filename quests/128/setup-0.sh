set -euo pipefail
cd ~/quest
cat > claim.yaml <<'DQ_ASSET'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ledger
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 16Mi
DQ_ASSET
python3 - claim.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f claim.yaml
cat > ledger.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ledger
  template:
    metadata:
      labels:
        app: ledger
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
        - sh
        - -c
        - test -s /data/ledger.txt || printf "ticket,units\nnorth,7\nsouth,3\n" > /data/ledger.txt; exec
          httpd -f -p 8080 -h /data
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
        - name: ledger
          mountPath: /data
      volumes:
      - name: ledger
        persistentVolumeClaim:
          claimName: ledger
      terminationGracePeriodSeconds: 1
DQ_ASSET
python3 - ledger.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f ledger.yaml
cat > service.yaml <<'DQ_ASSET'
apiVersion: v1
kind: Service
metadata:
  name: ledger
spec:
  selector:
    app: ledger
  ports:
  - name: http
    port: 8080
    targetPort: 8080
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
kubectl rollout status deployment/ledger --timeout=90s
kubectl rollout status deployment/client --timeout=90s
kubectl exec deployment/ledger -- sha256sum /data/ledger.txt | awk '{print $1}' > original-ledger.sha256
kubectl get pvc ledger -o jsonpath='{.metadata.uid}' > original-pvc-uid
python3 -I - <<'DQ_CHECKPOINT_SEED'
import copy,json,secrets,subprocess
from pathlib import Path
def get(kind,name):
    return json.loads(subprocess.check_output(['kubectl','get',kind,name,'-o','json'],text=True))
def create(value):
    subprocess.run(['kubectl','create','-f','-'],input=json.dumps(value),text=True,check=True)
ledger=get('deployment','ledger')
create({'apiVersion':'v1','kind':'PersistentVolumeClaim','metadata':{'name':'summary'},
        'spec':{'accessModes':['ReadWriteOnce'],'resources':{'requests':{'storage':'16Mi'}}}})
reader=copy.deepcopy(ledger)
reader.pop('status',None)
reader['metadata']={'name':'summary'}
reader['spec']['selector']={'matchLabels':{'app':'summary'}}
reader['spec']['template']['metadata']={'labels':{'app':'summary'}}
pod=reader['spec']['template']['spec']
pod['automountServiceAccountToken']=False
pod['containers'][0]['command']=['sh','-c','exec httpd -f -p 8080 -h /data']
pod['volumes']=[{'name':'ledger','persistentVolumeClaim':{'claimName':'summary'}}]
create(reader)
subprocess.run(['kubectl','rollout','status','deployment/summary','--timeout=90s'],check=True)
create({'apiVersion':'v1','kind':'Service','metadata':{'name':'summary'},
        'spec':{'selector':{'app':'summary'},'ports':[{'port':8080,'targetPort':8080}]}})
marker=secrets.token_hex(12)
writer=copy.deepcopy(reader)
writer['metadata']={'name':'journal-writer'}
writer['spec']['selector']={'matchLabels':{'app':'journal-writer'}}
writer['spec']['template']['metadata']={'labels':{'app':'journal-writer'}}
pod=writer['spec']['template']['spec']
worker=pod['containers'][0]
worker['command']=['sh','-c','set -eu\nwhile :; do\n if mkdir /journal/.checkpoint-lock 2>/dev/null; then\n  trap \'rmdir /journal/.checkpoint-lock 2>/dev/null || true\' EXIT INT TERM\n  n=$(cat /journal/generation 2>/dev/null || printf 0); n=$((n+1))\n  printf \'marker\tgeneration\troute\tunits\n%s\t%s\tnorth\t%s\n%s\t%s\tsouth\t%s\n%s\t%s\teast\t%s\n\' "$MARKER" "$n" "$n" "$MARKER" "$n" "$((n*2))" "$MARKER" "$n" "$((n+3))" > /journal/orders.next\n  mv /journal/orders.next /journal/orders.tsv\n  printf orders-published > /journal/writer-phase\n  sleep 0.3\n  printf \'{"marker":"%s","generation":%s,"total":%s}\n\' "$MARKER" "$n" "$((n*4+3))" > /index/summary.next\n  mv /index/summary.next /index/summary.json\n  printf \'%s\' "$n" > /journal/generation\n  printf committed > /journal/writer-phase\n  rmdir /journal/.checkpoint-lock\n  trap - EXIT INT TERM\n fi\n sleep 0.2\ndone']
worker['env']=[{'name':'MARKER','value':marker}]
worker['volumeMounts']=[{'name':'journal','mountPath':'/journal'},{'name':'index','mountPath':'/index'}]
pod['volumes']=[{'name':'journal','persistentVolumeClaim':{'claimName':'ledger'}},
                {'name':'index','persistentVolumeClaim':{'claimName':'summary'}}]
create(writer)
subprocess.run(['kubectl','rollout','status','deployment/journal-writer','--timeout=90s'],check=True)
subprocess.run(['kubectl','exec','deployment/ledger','--','sh','-c',
                'for i in $(seq 1 90); do test -s /data/orders.tsv && test -s /data/generation && exit 0; sleep 0.1; done; exit 1'],check=True)
contract={'schema':1,'originalLedgerArchive':'ledger.tar','checkpointArchive':'checkpoint.tar',
          'maximumEntryBytes':65536,'marker':marker,'routes':['north','south','east'],
          'ordersColumns':['marker','generation','route','units'],
          'summaryFields':['marker','generation','total'],'matchingGenerations':True,
          'summaryEqualsOrderUnitsSum':True,'positiveGenerationAndUnits':True,'integerGenerationAndUnits':True,'integerSummaryTotal':True,
          'writer':'journal-writer','client':'client',
          'checkpointProtocol':{'writerUsesExclusiveDirectory':True,
                                 'lockPathInsideLedger':'/data/.checkpoint-lock',
                                 'writerPublishesTwoFilesSeparately':True},
          'preserveExistingClaimsAndDeployments':True,'preserveProvidedWorkerImages':True,
          'recoveryWriterReplicas':0,'regularArchiveMembersOnly':True,
          'stores':[{'deployment':'ledger','claim':'ledger','path':'/data/orders.tsv',
                     'entry':'orders.tsv','url':'http://ledger:8080/orders.tsv'},
                    {'deployment':'summary','claim':'summary','path':'/data/summary.json',
                     'entry':'summary.json','url':'http://summary:8080/summary.json'}]}
deployments={}
for name in ('ledger','client','summary','journal-writer'):
    value=get('deployment',name)
    deployments[name]={'uid':value['metadata']['uid'],
                       'image':next(item['image'] for item in value['spec']['template']['spec']['containers'] if item['name']=='worker')}
facts={'contract':contract,'deployments':deployments,
       'claims':{name:get('pvc',name)['metadata']['uid'] for name in ('ledger','summary')}}
Path('checkpoint-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
Path('checkpoint-identities.json').write_text(json.dumps(facts)+'\n')
DQ_CHECKPOINT_SEED
rm -f claim.yaml ledger.yaml service.yaml client.yaml
