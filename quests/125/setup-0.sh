set -euo pipefail
cd ~/quest
cat > controller-sa.yaml <<'DQ_ASSET'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: controller
automountServiceAccountToken: false
DQ_ASSET
python3 - controller-sa.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f controller-sa.yaml
cat > controller.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: controller
spec:
  replicas: 1
  selector:
    matchLabels:
      app: controller
  template:
    metadata:
      labels:
        app: controller
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
        volumeMounts:
        - name: credential
          mountPath: /credential
          readOnly: true
      serviceAccountName: controller
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 1
      volumes:
      - name: credential
        projected:
          sources:
          - serviceAccountToken:
              path: token
              expirationSeconds: 600
              audience: https://kubernetes.default.svc.cluster.local
DQ_ASSET
python3 - controller.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f controller.yaml
cat > observer-sa.yaml <<'DQ_ASSET'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: observer
automountServiceAccountToken: false
DQ_ASSET
python3 - observer-sa.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f observer-sa.yaml
cat > observer.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: observer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: observer
  template:
    metadata:
      labels:
        app: observer
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
        volumeMounts:
        - name: credential
          mountPath: /credential
          readOnly: true
      serviceAccountName: observer
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 1
      volumes:
      - name: credential
        projected:
          sources:
          - serviceAccountToken:
              path: token
              expirationSeconds: 600
              audience: https://kubernetes.default.svc.cluster.local
DQ_ASSET
python3 - observer.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f observer.yaml
cat > role.yaml <<'DQ_ASSET'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: station-reader
rules:
- apiGroups:
  - ''
  resources:
  - configmaps
  - secrets
  verbs:
  - get
  - list
  - watch
DQ_ASSET
python3 - role.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f role.yaml
cat > binding.yaml <<'DQ_ASSET'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: station-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: station-reader
subjects:
- kind: ServiceAccount
  name: controller
  namespace: __NAMESPACE__
- kind: ServiceAccount
  name: observer
  namespace: __NAMESPACE__
DQ_ASSET
python3 - binding.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
sed -i "s/__NAMESPACE__/$DQ_NAMESPACE/g" binding.yaml
kubectl apply -f binding.yaml
cat > route.yaml <<'DQ_ASSET'
apiVersion: v1
kind: ConfigMap
metadata:
  name: route
data:
  route: north-125
DQ_ASSET
python3 - route.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f route.yaml
cat > offlimits.yaml <<'DQ_ASSET'
apiVersion: v1
kind: ConfigMap
metadata:
  name: offlimits
data:
  route: closed
DQ_ASSET
python3 - offlimits.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f offlimits.yaml
cat > secret.yaml <<'DQ_ASSET'
apiVersion: v1
kind: Secret
metadata:
  name: control
stringData:
  value: synthetic-control
DQ_ASSET
python3 - secret.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f secret.yaml
kubectl rollout status deployment/controller --timeout=90s
kubectl rollout status deployment/observer --timeout=90s
kubectl config view --minify --raw -o json | jq -r '.clusters[0].cluster["certificate-authority-data"]' | base64 -d > api-ca.pem
kubectl config view --minify -o json | jq -r '.clusters[0].cluster.server' > api-endpoint
python3 -I - <<'DQ_AUTHORITY_SEED'
import copy,json,os,secrets,subprocess
from pathlib import Path
def get(kind,name):
    return json.loads(subprocess.check_output(['kubectl','get',kind,name,'-o','json'],text=True))
def apply(value):
    subprocess.run(['kubectl','apply','-f','-'],input=json.dumps(value),text=True,check=True)
controller=get('deployment','controller')
consumers=[]
for name,record,prefix in [('publisher','release-plan','release'),('sampler','sampling','sample')]:
    response=prefix+'-'+secrets.token_hex(8)
    apply({'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':record},'data':{'route':response}})
    value=copy.deepcopy(controller);value['metadata']={'name':name};value.pop('status',None)
    value['spec']['selector']['matchLabels']={'app':name}
    value['spec']['template']['metadata']={'labels':{'app':name}}
    value['spec']['revisionHistoryLimit']=0
    apply(value)
    subprocess.run(['kubectl','rollout','status','deployment/'+name,'--timeout=90s'],check=True)
    consumers.append({'deployment':name,'configMap':record,'key':'route','response':response})
contract={'schema':1,'control':{'deployment':'controller','serviceAccount':'controller','configMap':'route','response':'north-125'},'observer':{'deployment':'observer','serviceAccount':'observer'},'consumers':consumers,'credential':{'container':'worker','path':'/credential/token'},'reservedServiceAccounts':['controller','observer','default','player'],'distinctConsumerIdentities':True,'namespaceRolesOnly':True,'preserveProvidedWorkloadsAndControlIdentities':True}
Path('authority-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
identities={};images={};accounts={}
for name in ['controller','observer']+[c['deployment'] for c in consumers]:
    value=get('deployment',name);identities['deployment/'+name]=value['metadata']['uid']
    images[name]=next(c['image'] for c in value['spec']['template']['spec']['containers'] if c['name']=='worker')
    if name in ('controller','observer'):
        accounts[name]=value['spec']['template']['spec']['serviceAccountName']
        identities['serviceaccount/'+accounts[name]]=get('serviceaccount',accounts[name])['metadata']['uid']
Path('authority-identities.json').write_text(json.dumps({'contract':contract,'identities':identities,'images':images,'originalAccounts':accounts})+'\n')
DQ_AUTHORITY_SEED
rm -f controller-sa.yaml observer-sa.yaml controller.yaml observer.yaml role.yaml binding.yaml route.yaml offlimits.yaml secret.yaml
