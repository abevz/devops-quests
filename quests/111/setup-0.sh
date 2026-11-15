set -euo pipefail
cd ~/quest
cat > shelf.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: shelf
spec:
  replicas: 1
  selector:
    matchLabels:
      app: shelf
  template:
    metadata:
      labels:
        app: shelf
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
        - test -s /data/index.html || printf "%s\n" ledger-111 > /data/index.html; exec httpd -f -p 8080
          -h /data
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
      terminationGracePeriodSeconds: 1
  serviceName: shelf
  volumeClaimTemplates:
  - metadata:
      name: ledger
    spec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 16Mi
DQ_ASSET
python3 - shelf.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f shelf.yaml
cat > service.yaml <<'DQ_ASSET'
apiVersion: v1
kind: Service
metadata:
  name: shelf
spec:
  selector:
    app: shelf
  ports:
  - name: http
    port: 8080
    targetPort: 8080
  clusterIP: None
DQ_ASSET
python3 - service.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f service.yaml
kubectl rollout status statefulset/shelf --timeout=90s
kubectl get statefulset shelf -o jsonpath='{.metadata.uid}' > original-statefulset-uid
kubectl get pvc ledger-shelf-0 -o jsonpath='{.metadata.uid}' > original-pvc-uid
kubectl get pod shelf-0 -o jsonpath='{.metadata.uid}' > original-pod-uid
kubectl patch statefulset shelf --type=json -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["sh", "-c", "exec httpd -f -p 8099 -h /data"]}]'

kubectl rollout status statefulset/shelf --timeout=90s
cat > discovery-contract.json <<'DQ_DISCOVERY_CONTRACT'
{
  "schema": 1,
  "consumer": "inspector",
  "container": "worker",
  "port": 8080,
  "response": "ledger-111",
  "preserveStatefulSetAndClaim": true,
  "useOrdinalDiscovery": true,
  "doNotMountSourceClaim": true
}
DQ_DISCOVERY_CONTRACT
python3 -I - <<'DQ_DISCOVERY_FACTS'
import json,subprocess
from pathlib import Path
source=json.loads(subprocess.check_output(['kubectl','get','statefulset','shelf','-o','json'],text=True))
pod=json.loads(subprocess.check_output(['kubectl','get','pod','shelf-0','-o','json'],text=True))
worker=next(c for c in pod['spec']['containers'] if c['name']=='worker')
mount=next(m for m in worker['volumeMounts'] if m['mountPath']=='/data')
volume=next(v for v in pod['spec']['volumes'] if v['name']==mount['name'])
facts={'contract':json.loads(Path('discovery-contract.json').read_text()),'source':{'statefulSet':'shelf','pod':'shelf-0','service':source['spec']['serviceName'],'claim':volume['persistentVolumeClaim']['claimName']},'image':worker['image']}
Path('discovery-identities.json').write_text(json.dumps(facts)+'\n')
DQ_DISCOVERY_FACTS
rm -f shelf.yaml service.yaml
