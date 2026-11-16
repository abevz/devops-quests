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
        - mkdir -p /tmp/site; printf "%s\n" "north-68" > /tmp/site/index.html; exec httpd -f -p 8080 -h
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
        readinessProbe:
          httpGet:
            path: /
            port: 9090
          initialDelaySeconds: 1
          periodSeconds: 1
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
cp release-commit baseline-commit


mkdir -p publication
printf 'north-68\n' > publication/index.html
printf '%s\n' '{"generation":"approved-68","route":"north","consumer":"board"}' > publication/contract.json
for _ in $(seq 1 60); do
 if kubectl get deployment board >/dev/null 2>&1; then break; fi
 sleep 1
done
kubectl get deployment board -o jsonpath='{.metadata.uid}' > original-deployment-uid

python3 -I - <<'DQ_PUBLICATION_RECEIPT'
import json,os,subprocess
from pathlib import Path
deployment=json.loads(subprocess.check_output(['kubectl','get','deployment','board','-o','json']))
app=json.loads(subprocess.check_output(['kubectl','get','application','board','-o','json']))
worker=next(c for c in deployment['spec']['template']['spec']['containers'] if c['name']=='worker')
receipt={'index':Path('publication/index.html').read_text(),
 'contract':json.loads(Path('publication/contract.json').read_text()),
 'applicationUID':app['metadata']['uid'],'deploymentUID':deployment['metadata']['uid'],
 'image':worker['image'],'repoURL':os.environ['GIT_URL'],
 'sourceDirectory':'manifests','providedServer':'httpd','publicationAtServerDocumentRoot':True,
 'publicationFiles':['index.html','contract.json'],'sourceTypes':['configMap','projected'],
 'readOnlyPublicationProjection':True,'publishedAndLiveProjectionAgree':True,
 'preserveApplicationDeploymentAndImage':True,'observesCurrentStateOnly':True}
Path('publication-contract.json').write_text(json.dumps(receipt,indent=2)+'\n')
DQ_PUBLICATION_RECEIPT
