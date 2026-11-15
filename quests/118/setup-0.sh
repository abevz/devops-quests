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
        - mkdir -p /tmp/site; printf "%s\n" "north-118" > /tmp/site/index.html; exec httpd -f -p 8080
          -h /tmp/site
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
cat > service.yaml <<'DQ_ASSET'
apiVersion: v1
kind: Service
metadata:
  name: board
spec:
  selector:
    app: retired
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
kubectl rollout status deployment/board --timeout=90s
kubectl rollout status deployment/client --timeout=90s
cat > diagnosis.json <<'DIAGNOSIS'
{"fault":"proxy-down"}
DIAGNOSIS
python3 -I - <<'DQ_VIP_SEED'
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

service=get('service','board')
contract={'schema':1,'service':'board','protectedWorkload':'board','caller':'client',
          'servicePort':8080,'applicationPort':8080,'preserveServiceUIDAndVIP':True,
          'preserveExistingWorkloads':True,'preserveProvidedWorkerImages':True,
          'currentOwnedEndpointTargets':True,'desiredAndEffectiveTargetMapping':True,'observesCurrentStateOnly':True}
facts={'contract':contract,'serviceUID':service['metadata']['uid'],'vip':service['spec']['clusterIP'],
       'deployments':deployments(['board','client'])}
Path('vip-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
Path('vip-identities.json').write_text(json.dumps(facts)+'\n')
DQ_VIP_SEED
rm -f board.yaml service.yaml client.yaml
