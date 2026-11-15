set -euo pipefail
cd ~/quest
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
            cpu: 150m
            memory: 16Mi
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
cat > quota.yaml <<'DQ_ASSET'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: station
spec:
  hard:
    requests.cpu: 200m
    limits.cpu: 400m
    requests.memory: 32Mi
    limits.memory: 64Mi
    pods: '2'
DQ_ASSET
python3 - quota.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f quota.yaml
cat > defaults.yaml <<'DQ_ASSET'
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
spec:
  limits:
  - type: Container
    default:
      cpu: 400m
      memory: 32Mi
    defaultRequest:
      cpu: 300m
      memory: 16Mi
DQ_ASSET
python3 - defaults.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f defaults.yaml
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
        - sh
        - -c
        - mkdir -p /tmp/site; printf "%s\n" "north-126" > /tmp/site/index.html; exec httpd -f -p 8080
          -h /tmp/site
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
      terminationGracePeriodSeconds: 1
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
    targetPort: 8080
DQ_ASSET
python3 - service.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f service.yaml

cat > admission-contract.json <<'DQ_ADMISSION_CONTRACT'
{
  "schema": 1,
  "quota": "station",
  "defaults": "defaults",
  "workloads": [
    "client",
    "board"
  ],
  "replicas": 1,
  "admitted": {
    "requests": {
      "cpu": "100m",
      "memory": "16Mi"
    },
    "limits": {
      "cpu": "200m",
      "memory": "32Mi"
    }
  },
  "templatesUseDefaults": true,
  "preserveQuotaAndWorkloads": true
}
DQ_ADMISSION_CONTRACT
python3 -I - <<'DQ_ADMISSION_FACTS'
import json,subprocess
from pathlib import Path
contract=json.loads(Path('admission-contract.json').read_text())
identities={};images={}
for kind,name in [('resourcequota',contract['quota'])]+[('deployment',name) for name in contract['workloads']]:
    value=json.loads(subprocess.check_output(['kubectl','get',kind,name,'-o','json'],text=True))
    identities[kind+'/'+name]=value['metadata']['uid']
    if kind=='deployment':
        images[name]=next(c['image'] for c in value['spec']['template']['spec']['containers'] if c['name']=='worker')
Path('admission-identities.json').write_text(json.dumps({'contract':contract,'identities':identities,'images':images})+'\n')
DQ_ADMISSION_FACTS
rm -f client.yaml quota.yaml defaults.yaml board.yaml service.yaml
