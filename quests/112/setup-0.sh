set -euo pipefail
cd ~/quest
cat > handler.yaml <<'DQ_ASSET'
apiVersion: v1
kind: ConfigMap
metadata:
  name: work-handler
data:
  process: |
    #!/bin/sh
    printf 'Content-Type: text/plain\r\n\r\n'
    i=0
    while [ "$i" -lt 30000 ]; do i=$((i+1)); done
    printf '%s\n' north-112
    printf '%s\n' completed >> /tmp/work-completions
DQ_ASSET
kubectl apply -f handler.yaml
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
        - mkdir -p /tmp/site/cgi-bin; cp /runtime/process /tmp/site/cgi-bin/process; chmod 0555 /tmp/site/cgi-bin/process;
          printf "%s\n" north-112 > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site
        resources:
          requests:
            cpu: '0'
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
        - name: handler
          mountPath: /runtime
          readOnly: true
      terminationGracePeriodSeconds: 1
      volumes:
      - name: handler
        configMap:
          name: work-handler
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
cat > hpa.yaml <<'DQ_ASSET'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: board
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: board-retired
  minReplicas: 1
  maxReplicas: 2
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
DQ_ASSET
python3 - hpa.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f hpa.yaml
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

cat > autoscaling-contract.json <<'DQ_LOAD_CONTRACT'
{
  "schema": 1,
  "server": "board",
  "client": "client",
  "hpa": "board",
  "port": 8080,
  "handler": {
    "configMap": "work-handler",
    "key": "process",
    "path": "/tmp/site/cgi-bin/process",
    "progress": "/tmp/work-completions",
    "endpoint": "/cgi-bin/process"
  },
  "cpu": {
    "request": "100m",
    "limit": "200m",
    "targetUtilization": 50
  },
  "replicas": {
    "min": 1,
    "max": 2
  },
  "response": "north-112",
  "preserveProvidedWorkloadsAndHPA": true,
  "preserveProvidedHandler": true
}
DQ_LOAD_CONTRACT
python3 -I - <<'DQ_LOAD_FACTS'
import hashlib,json,subprocess
from pathlib import Path
contract=json.loads(Path('autoscaling-contract.json').read_text());identities={};images={}
for kind,name in [('deployment',contract['server']),('deployment',contract['client']),('hpa',contract['hpa']),('configmap',contract['handler']['configMap'])]:
    value=json.loads(subprocess.check_output(['kubectl','get',kind,name,'-o','json'],text=True))
    identities[kind+'/'+name]=value['metadata']['uid']
    if kind=='deployment':
        images[name]=next(c['image'] for c in value['spec']['template']['spec']['containers'] if c['name']=='worker')
    if kind=='configmap':
        handler_sha256=hashlib.sha256(value['data'][contract['handler']['key']].encode()).hexdigest()
Path('autoscaling-identities.json').write_text(json.dumps({'contract':contract,'identities':identities,'images':images,'handlerSHA256':handler_sha256})+'\n')
DQ_LOAD_FACTS
rm -f handler.yaml board.yaml service.yaml hpa.yaml client.yaml
