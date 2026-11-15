set -euo pipefail
cd ~/quest
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
        - mkdir -p /tmp/site; printf "%s\n" "north-62" > /tmp/site/index.html; exec httpd -f -p 8080 -h
          /tmp/site
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
cat > dispatcher.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dispatcher
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dispatcher
  template:
    metadata:
      labels:
        app: dispatcher
        role: retired
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
python3 - dispatcher.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f dispatcher.yaml
cat > visitor.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: visitor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: visitor
  template:
    metadata:
      labels:
        app: visitor
        role: guest
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
DQ_ASSET
python3 - visitor.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f visitor.yaml
cat > policy.yaml <<'DQ_ASSET'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: board-ingress
spec:
  podSelector:
    matchLabels:
      app: board
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: dispatcher
    ports:
    - protocol: TCP
      port: 9090
DQ_ASSET
python3 - policy.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f policy.yaml
kubectl rollout status deployment/board --timeout=60s
kubectl rollout status deployment/dispatcher --timeout=60s
kubectl rollout status deployment/visitor --timeout=60s
sleep 3
python3 -I - <<'DQ_ISOLATION_SEED'
import json,subprocess
from pathlib import Path
def get(kind,name):
    return json.loads(subprocess.check_output(['kubectl','get',kind,name,'-o','json'],text=True))
def deployments(names):
    result={}
    for name in names:
        value=get('deployment',name)
        result[name]={'uid':value['metadata']['uid'],
                      'image':next(item['image'] for item in value['spec']['template']['spec']['containers'] if item['name']=='worker')}
    return result

contract={'schema':1,'policy':'board-ingress','permittedCaller':'dispatcher',
          'protectedWorkload':'board','excludedCaller':'visitor',
          'preserveExistingPolicyAndWorkloads':True,'preserveProvidedWorkerImages':True,
          'desiredAndCurrentCallerMatchRetainedPolicy':True,'currentCallerPodsReady':True,
          'observesCurrentStateOnly':True}
facts={'contract':contract,'policyUID':get('networkpolicy','board-ingress')['metadata']['uid'],
       'deployments':deployments(['board','dispatcher','visitor'])}
Path('isolation-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
Path('isolation-identities.json').write_text(json.dumps(facts)+'\n')
DQ_ISOLATION_SEED
rm -f board.yaml service.yaml dispatcher.yaml visitor.yaml policy.yaml
