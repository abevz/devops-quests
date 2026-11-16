set -euo pipefail
cd ~/quest
source platform.env
mkdir -p repository/manifests
cat > repository/manifests/board.yaml <<'DQ_ASSET'
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
        - mkdir -p /tmp/site; cp /etc/publication/notice /tmp/site/index.html; exec
          httpd -f -p 8080 -h /tmp/site
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
        - name: publication
          mountPath: /etc/publication
          readOnly: true
      volumes:
      - name: publication
        configMap:
          name: board-publication
DQ_ASSET
python3 - repository/manifests/board.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
mkdir -p repository/manifests
cat > repository/manifests/service.yaml <<'DQ_ASSET'
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
python3 - repository/manifests/service.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
cat > repository/manifests/publication.yaml <<'DQ_PUBLICATION'
apiVersion: v1
kind: ConfigMap
metadata:
  name: board-publication
data:
  notice: initial-75
DQ_PUBLICATION
cd repository
git remote add origin "$GIT_URL"
git add .
git commit -m 'Publish station board'
git push -u origin main
git rev-parse HEAD > ../release-commit
cd ..
cat > application.yaml <<'DQ_ASSET'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: board
spec:
  project: station
  source:
    repoURL: __GIT_URL__
    path: manifests
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
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if kubectl get application board -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null && kubectl rollout status deployment/board --timeout=2s >/dev/null 2>&1; then break; fi
 sleep 1
done
cp release-commit initial-commit
source platform.env
source webhook.env
GITEA_API="${GIT_URL%/rail/station.git}/api/v1/repos/rail/station"
jq -n --arg url "$WEBHOOK_URL-retired" --arg secret "$WEBHOOK_SECRET" '{type:"gogs",config:{url:$url,content_type:"json",secret:$secret},events:["push"],branch_filter:"main",active:true}' > hook-create.json
curl -fsS -u "$GIT_USER:$GIT_PASSWORD" -H 'Content-Type: application/json' --request POST --data-binary @hook-create.json "$GITEA_API/hooks" > hook-created.json
jq -er .id hook-created.json > hook-id
python3 - <<'RELEASE'
from pathlib import Path
p=Path('repository/manifests/publication.yaml');p.write_text(p.read_text().replace('initial-75','north-75'))
RELEASE
cd repository
git add manifests/publication.yaml
git commit -m 'Publish webhook-delivered board'
git push origin main
git rev-parse HEAD > ../release-commit
cd ..
sleep 5

python3 -I - <<'DQ_PUBLICATION_CONTRACT'
import json,subprocess,yaml
from pathlib import Path
def k(*args):
 return json.loads(subprocess.check_output(['kubectl',*args,'-o','json'],timeout=3))
revision=Path('release-commit').read_text().strip()
approved=yaml.safe_load(subprocess.check_output(['git','-C','repository','show',revision+':manifests/publication.yaml'],text=True,timeout=3))
contract={'deployment':k('get','deployment','board'),'application':k('get','application','board'),
'publication_uid':k('get','configmap',approved['metadata']['name'])['metadata']['uid'],
'approved':approved,'release_commit':revision,'source_file':'manifests/publication.yaml'}
Path('webhook-publication.json').write_text(json.dumps(contract))
DQ_PUBLICATION_CONTRACT
