set -euo pipefail
cd ~/quest
source platform.env
git -C repository remote add origin "$GIT_URL"
cat > relay.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: relay
spec:
  replicas: 2
  selector:
    matchLabels:
      app: relay
  template:
    metadata:
      labels:
        app: relay
    spec:
      containers:
      - command:
        - sh
        - -c
        - mkdir -p /tmp/www; echo relay-85 >/tmp/www/index.html; exec httpd -f -p
          8080 -h /tmp/www
        image: ${DQ_APP_IMAGE}
        imagePullPolicy: Never
        lifecycle:
          preStop:
            exec:
              command:
              - sleep
              - '10'
        name: worker
        ports:
        - containerPort: 8080
        resources:
          limits:
            memory: 64Mi
          requests:
            cpu: 10m
            memory: 16Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      terminationGracePeriodSeconds: 20
---
apiVersion: v1
kind: Service
metadata:
  name: relay
spec:
  selector:
    app: relay
  ports:
  - port: 8080
    targetPort: 8080
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' relay.yaml
kubectl apply -f relay.yaml
kubectl rollout status deployment/relay --timeout=90s
cat > companion.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: companion
spec:
  replicas: 2
  selector:
    matchLabels:
      app: companion
  template:
    metadata:
      labels:
        app: companion
    spec:
      containers:
      - command:
        - sh
        - -c
        - mkdir -p /tmp/www; echo companion-85 >/tmp/www/index.html; exec httpd -f
          -p 8080 -h /tmp/www
        image: ${DQ_APP_IMAGE}
        imagePullPolicy: Never
        lifecycle:
          preStop:
            exec:
              command:
              - sleep
              - '10'
        name: worker
        ports:
        - containerPort: 8080
        resources:
          limits:
            memory: 64Mi
          requests:
            cpu: 10m
            memory: 16Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      terminationGracePeriodSeconds: 20
---
apiVersion: v1
kind: Service
metadata:
  name: companion
spec:
  selector:
    app: companion
  ports:
  - port: 8080
    targetPort: 8080
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' companion.yaml
kubectl apply -f companion.yaml
kubectl rollout status deployment/companion --timeout=90s
mkdir -p repository/policies
cat > repository/policies/budget.yaml <<'DQ_ASSET'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: relay
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: relay
DQ_ASSET
git -C repository add policies
git -C repository commit -m 'Track maintenance policy'
git -C repository push origin main
cat > companion-budget.yaml <<'DQ_ASSET'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: companion
spec:
  minAvailable: 1
  selector:
    matchExpressions:
    - key: app
      operator: In
      values: [relay, companion]
DQ_ASSET
kubectl apply -f companion-budget.yaml
cat > application.yaml <<'DQ_ASSET'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: maintenance
spec:
  project: station
  source:
    repoURL: __GIT_URL__
    path: policies
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: __NAMESPACE__
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
DQ_ASSET
python3 - <<'APP'
import os
from pathlib import Path
p=Path('application.yaml');p.write_text(p.read_text().replace('__GIT_URL__',os.environ['GIT_URL']).replace('__NAMESPACE__',os.environ['DQ_NAMESPACE']))
APP
kubectl apply -f application.yaml
for i in $(seq 1 90); do
 if kubectl get application maintenance -o json | jq -e --arg rev "$(git -C repository rev-parse HEAD)" '.status.sync.revision==$rev and .status.sync.status=="Synced"' >/dev/null && kubectl get pdb relay >/dev/null; then break; fi
 sleep 1
done
kubectl get application maintenance -o json | jq -e --arg rev "$(git -C repository rev-parse HEAD)" '.status.sync.revision==$rev and .status.sync.status=="Synced"' >/dev/null
kubectl get deployment,service,pdb,application,pods -o json > initial-resources.json
python3 - <<'IDENTITIES'
import json
from pathlib import Path
items=json.loads(Path('initial-resources.json').read_text())['items']
objects={o['kind']+'/'+o['metadata']['name']:o for o in items}
facts={'identities':{k:o['metadata']['uid'] for k,o in objects.items() if o['kind']!='Pod'},'source':objects['Application/maintenance']['spec']['source'],'pools':{}}
for name in ['relay','companion']:
 facts['pools'][name]=[{'name':o['metadata']['name'],'uid':o['metadata']['uid']} for o in items if o['kind']=='Pod' and o['metadata'].get('labels',{}).get('app')==name]
 assert len(facts['pools'][name])==2
Path('maintenance-baseline.json').write_text(json.dumps(facts,indent=2)+'\n')
Path('original-pod-uids.json').write_text(json.dumps([p['uid'] for pool in facts['pools'].values() for p in pool])+'\n')
IDENTITIES
rm initial-resources.json
