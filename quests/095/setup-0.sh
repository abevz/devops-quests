set -euo pipefail
cd ~/quest
source platform.env
git -C repository remote add origin "$GIT_URL"
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
        - mkdir -p /tmp/site; printf "%s\n" "north-95" > /tmp/site/index.html; exec httpd -f -p 8080 -h
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
git -C repository add .
git -C repository commit -m 'Record healthy baseline'
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
cp release-commit healthy-commit
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
python3 - <<'BAD'
import yaml
from pathlib import Path
p=Path('repository/manifests/board.yaml');m=yaml.safe_load(p.read_text());m['spec']['template']['spec']['containers'][0]['readinessProbe']={'httpGet':{'path':'/','port':8099},'initialDelaySeconds':0,'periodSeconds':1};p.write_text(yaml.safe_dump(m,sort_keys=False))
BAD
git -C repository add .
git -C repository commit -m 'Introduce faulty probe'
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
cp release-commit faulty-commit
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 60); do
 if kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" '.status.sync.revision==$rev' >/dev/null; then break; fi
 sleep 1
done


source platform.env
python3 -I - <<'CONSUMERS'
import json,os,yaml
from pathlib import Path
approved={'schema':2,'generation':'approved-95','route':'north'}
Path('current-publication.json').write_text(json.dumps(approved,sort_keys=True)+'\n')
for lane in ['a','b']:
 name='reader-'+lane
 body=json.dumps({'schema':1,'generation':'previous-95','route':'north'},sort_keys=True)+'\n'
 cm={'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':name+'-publication'},'data':{'index.html':body}}
 worker={'name':'worker','image':os.environ['DQ_APP_IMAGE'],'imagePullPolicy':'Never','command':['httpd','-f','-p','8080','-h','/publication'],
 'resources':{'requests':{'cpu':'10m','memory':'8Mi'},'limits':{'memory':'32Mi'}},
 'securityContext':{'allowPrivilegeEscalation':False,'capabilities':{'drop':['ALL']}},
 'readinessProbe':{'httpGet':{'path':'/','port':8080},'periodSeconds':1},
 'volumeMounts':[{'name':'publication','mountPath':'/publication','readOnly':True}]}
 deployment={'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':name},'spec':{'replicas':1,'selector':{'matchLabels':{'app':name}},
 'template':{'metadata':{'labels':{'app':name}},'spec':{'securityContext':{'runAsNonRoot':True,'runAsUser':1000,'seccompProfile':{'type':'RuntimeDefault'}},
 'containers':[worker],'volumes':[{'name':'publication','configMap':{'name':name+'-publication','defaultMode':0o444}}]}}}}
 service={'apiVersion':'v1','kind':'Service','metadata':{'name':name},'spec':{'selector':{'app':name},'ports':[{'port':8080,'targetPort':8080}]}}
 folder=Path('repository/readers')/lane;folder.mkdir(parents=True,exist_ok=True)
 (folder/'resources.yaml').write_text(yaml.safe_dump_all([cm,deployment,service],sort_keys=False))
CONSUMERS
git -C repository add readers
git -C repository commit -m 'Record independently pinned publication consumers'
git -C repository push origin main
git -C repository rev-parse HEAD > consumer-baseline-commit
python3 -I - <<'APPLICATIONS'
import os,subprocess,yaml
from pathlib import Path
revision=Path('consumer-baseline-commit').read_text().strip()
apps=[]
for lane in ['a','b']:
 apps.append({'apiVersion':'argoproj.io/v1alpha1','kind':'Application','metadata':{'name':'reader-'+lane},'spec':{'project':'station',
 'source':{'repoURL':os.environ['GIT_URL'],'path':'readers/'+lane,'targetRevision':revision},
 'destination':{'server':'https://kubernetes.default.svc','namespace':os.environ['DQ_NAMESPACE']},
 'syncPolicy':{'automated':{'prune':True,'selfHeal':True}}}})
subprocess.run(['kubectl','apply','-f','-'],input=yaml.safe_dump_all(apps),text=True,check=True)
APPLICATIONS
for name in reader-a reader-b; do
 for _ in $(seq 1 90); do
  if kubectl get application "$name" -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null; then break; fi
  sleep 1
 done
 kubectl rollout status "deployment/$name" --timeout=60s
done
python3 -I - <<'IDENTITIES'
import json,subprocess
from pathlib import Path
receipts={}
for name in ['board','reader-a','reader-b']:
 for kind in ['application','deployment']:
  obj=json.loads(subprocess.check_output(['kubectl','get',kind,name,'-o','json']))
  receipts[kind+'/'+name]=obj['metadata']['uid']
Path('original-release-identities.json').write_text(json.dumps(receipts,indent=2)+'\n')
IDENTITIES

python3 -I - <<'DQ_ROLLBACK_RECEIPT'
import json,os,subprocess
from pathlib import Path
identities=json.loads(Path('original-release-identities.json').read_text())
consumers=[]
for lane in ['a','b']:
 name='reader-'+lane
 app=json.loads(subprocess.check_output(['kubectl','get','application',name,'-o','json']))
 live=json.loads(subprocess.check_output(['kubectl','get','deployment',name,'-o','json']))
 worker=next(c for c in live['spec']['template']['spec']['containers'] if c['name']=='worker')
 consumers.append({'name':name,'lane':lane,'path':'readers/'+lane,'project':app['spec']['project'],'destination':app['spec']['destination'],
  'program':{key:worker.get(key) for key in ['image','command','args']},'documentRoot':'/publication'})
receipt={'repoURL':os.environ['GIT_URL'],'originalIdentities':identities,
 'baselineCommit':Path('consumer-baseline-commit').read_text().strip(),
 'publication':json.loads(Path('current-publication.json').read_text()),'consumers':consumers,
 'immutableCommitPins':True,'preserveOriginalApplicationsAndDeployments':True,
 'preserveConsumerImagesAndPrograms':True,'publishApprovedProjectedConsumerData':True,
 'verifyEveryOwnedActivePod':True,'observesCurrentStateOnly':True}
Path('rollback-contract.json').write_text(json.dumps(receipt,indent=2)+'\n')
DQ_ROLLBACK_RECEIPT
