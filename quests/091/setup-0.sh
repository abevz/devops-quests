set -euo pipefail
cd ~/quest
source platform.env
git -C repository remote add origin "$GIT_URL"
mkdir -p repository/site
cat > repository/site/index.html <<'DQ_ASSET'
north-91
DQ_ASSET
git -C repository add .
git -C repository commit -m 'Record image source'
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
cp release-commit source-commit
mkdir -p image-context
cp repository/site/index.html image-context/index.html
mkdir -p image-context
cat > image-context/Dockerfile <<'DQ_ASSET'
ARG BASE
FROM ${BASE}
COPY index.html /opt/station/index.html
ARG REVISION
LABEL org.opencontainers.image.revision=$REVISION
DQ_ASSET
docker build --build-arg BASE="$PRIVATE_IMAGE" --build-arg REVISION="$(cat source-commit)" -t "$REGISTRY/parcel:source91" image-context
docker push "$REGISTRY/parcel:source91"
docker image inspect "$REGISTRY/parcel:source91" --format '{{json .RepoDigests}}' | jq -er --arg prefix "$REGISTRY/parcel@" '.[]|select(startswith($prefix))' > image-ref
jq -n --arg image "$(cat image-ref)" --arg commit "$(cat source-commit)" --arg repo "$GIT_URL" '{image:$image,commit:$commit,repo:$repo}' > release-evidence.json
kubectl create secret docker-registry registry-pull --docker-server="$REGISTRY" --docker-username="$REGISTRY_USER" --docker-password="$REGISTRY_PASSWORD" --dry-run=client -o json | kubectl apply -f -
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
        image: __RELEASE_IMAGE__
        imagePullPolicy: Always
        command:
        - sh
        - -c
        - exec httpd -f -p 8080 -h /opt/station
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
      imagePullSecrets:
      - name: registry-pull
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
python3 - <<'IMAGE'
from pathlib import Path
p=Path('repository/manifests/board.yaml');p.write_text(p.read_text().replace('__RELEASE_IMAGE__',Path('image-ref').read_text().strip()))
IMAGE
python3 - <<'PROVENANCE_CONSUMER'
import yaml,json
from pathlib import Path
p=Path('repository/manifests/board.yaml');deployment=yaml.safe_load(p.read_text())
worker=deployment['spec']['template']['spec']['containers'][0]
worker['volumeMounts']=[{'name':'provenance','mountPath':'/opt/station/provenance.json','subPath':'provenance.json','readOnly':True}]
deployment['spec']['template']['spec']['volumes']=[{'name':'provenance','configMap':{'name':'build-record'}}]
p.write_text(yaml.safe_dump(deployment,sort_keys=False))
record={'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'build-record'},'data':{'provenance.json':'{}'}}
Path('repository/manifests/provenance.yaml').write_text(yaml.safe_dump(record,sort_keys=False))
PROVENANCE_CONSUMER
git -C repository add .
git -C repository commit -m 'Deploy immutable source artifact'
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
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
 if kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" '.status.sync.revision==$rev and .status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null; then break; fi
 sleep 1
done
kubectl rollout status deployment/board --timeout=60s
cat > provenance.json <<'DQ_ASSET'
{}
DQ_ASSET
# Retain an immutable commitment for validation, never a copyable answer tuple.
python3 - <<'COMMITMENT'
import hashlib,json
from pathlib import Path
p=Path('release-evidence.json');value=json.loads(p.read_text())
digest=hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
p.write_text(json.dumps({'sha256':digest})+'\n')
COMMITMENT
rm -rf image-context
rm source-commit image-ref
