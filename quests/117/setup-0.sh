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
    app: static-board
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
kubectl rollout status deployment/client --timeout=90s
cat > static-pod.yaml <<'DQ_ASSET'
apiVersion: v1
kind: Pod
metadata:
  name: static-board
  namespace: __NAMESPACE__
  labels:
    app: static-board
spec:
  automountServiceAccountToken: false
  terminationGracePeriodSeconds: 1
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: board
    image: __DQ_APP_IMAGE__
    imagePullPolicy: Never
    command:
    - sh
    - -c
    - mkdir -p /tmp/site; echo north-117 > /tmp/site/index.html; exec httpd -f -p 8099 -h /tmp/site
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
    resources:
      requests:
        cpu: 10m
        memory: 8Mi
      limits:
        cpu: 200m
        memory: 32Mi
DQ_ASSET
python3 - static-pod.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
sed -i "s/__NAMESPACE__/$DQ_NAMESPACE/g" static-pod.yaml
python3 - <<'API_SHADOW'
import os,yaml
from pathlib import Path
pod=yaml.safe_load(Path('static-pod.yaml').read_text())
pod['metadata']['name']='static-board-'+os.environ['DQ_NODE_NAME']
pod['metadata']['labels']={'app':'legacy-board'}
pod['spec']['containers'][0]['command'][-1]=pod['spec']['containers'][0]['command'][-1].replace('north-117','legacy-117').replace('-p 8099','-p 8080')
Path('api-pod.yaml').write_text(yaml.safe_dump(pod,sort_keys=False))
API_SHADOW
kubectl apply -f api-pod.yaml
kubectl wait --for=condition=Ready "pod/static-board-$DQ_NODE_NAME" --timeout=90s
rm api-pod.yaml
