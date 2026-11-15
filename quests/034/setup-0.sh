set -euo pipefail
cd ~/quest
kubectl apply -f - <<'DQ_ROUTE_SOURCE'
apiVersion: v1
kind: ConfigMap
metadata:
  name: route-source
data:
  index.html: |
    north
DQ_ROUTE_SOURCE
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
            cpu: '1000'
            memory: 16Mi
          limits:
            cpu: '1000'
            memory: 64Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: route
          mountPath: /site
          readOnly: true
      terminationGracePeriodSeconds: 1
      volumes:
      - name: route
        emptyDir: {}
      - name: source
        configMap:
          name: route-source
      initContainers:
      - name: prepare-route
        image: __DQ_APP_IMAGE__
        imagePullPolicy: Never
        command:
        - sh
        - -c
        - cp /source/index.html /site/index.html
        resources:
          requests:
            cpu: '1000'
            memory: 8Mi
          limits:
            memory: 16Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: source
          mountPath: /source
          readOnly: true
        - name: route
          mountPath: /site
DQ_ASSET
python3 - board.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f board.yaml

python3 -I - <<'DQ_CPU_SEED'
import json,os,subprocess
from pathlib import Path
def get(kind,name):
    return json.loads(subprocess.run(['kubectl','get',kind,name,'-o','json'],capture_output=True,text=True,check=True,timeout=20).stdout)
contract={'deployment':'board','worker':'worker','initializer':'prepare-route','source':{'configMap':'route-source','key':'index.html'},'primary':{'requests':{'cpu':'100m','memory':'16Mi'},'limits':{'cpu':'300m','memory':'64Mi'}},'phaseRequestCeiling':'100m','interface':{'port':8080,'path':'/','body':'north\n'}}
source=get('configmap',contract['source']['configMap'])
identities={'deployment/board':get('deployment','board')['metadata']['uid'],'configmap/route-source':source['metadata']['uid']}
Path('cpu-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
Path('cpu-identities.json').write_text(json.dumps({'contract':contract,'identities':identities,'image':os.environ['DQ_APP_IMAGE'],'sourceData':source['data']},indent=2)+'\n')
Path('board.yaml').unlink()
DQ_CPU_SEED
