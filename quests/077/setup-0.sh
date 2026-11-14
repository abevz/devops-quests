set -euo pipefail
cd ~/quest
cat > board.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: board
spec:
  replicas: 2
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
        - mkdir -p /tmp/site; touch /tmp/site/ready; printf "%s\n" "north-77" > /tmp/site/index.html; exec httpd -f -p 8080 -h
          /tmp/site
        readinessProbe:
          exec:
            command: [sh, -c, "test -f /tmp/site/ready"]
          periodSeconds: 1
          failureThreshold: 1
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
        lifecycle:
          preStop:
            exec:
              command:
              - sleep
              - '10'
      terminationGracePeriodSeconds: 20
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
DQ_ASSET
python3 - client.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f client.yaml
cat > pdb.yaml <<'DQ_ASSET'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: board-budget
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: board
DQ_ASSET
python3 - pdb.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f pdb.yaml
kubectl rollout status deployment/board --timeout=60s
kubectl rollout status deployment/client --timeout=60s
kubectl get pods -l app=board -o json | jq '[.items[].metadata.uid]' > original-pod-uids.json
# A local readiness fault must be repaired without replacing either original Pod.
pod=$(kubectl get pods -l app=board -o jsonpath='{.items[0].metadata.name}')
kubectl exec "$pod" -- rm /tmp/site/ready
for i in $(seq 1 30); do
 if kubectl get pdb board-budget -o json | jq -e '.status.currentHealthy==1' >/dev/null; then break; fi
 sleep 1
done
kubectl get pdb board-budget -o json | jq -e '.status.currentHealthy==1' >/dev/null
