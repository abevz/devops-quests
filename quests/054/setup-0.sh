set -euo pipefail
source platform.env
mkdir -p repository/manifests
cat > repository/manifests/relay.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: relay
spec:
  replicas: 1
  selector:
    matchLabels:
      app: relay
  template:
    metadata:
      labels:
        app: relay
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: worker
        image: ${DQ_APP_IMAGE}
        imagePullPolicy: Never
        command:
        - sh
        - -c
        - mkdir -p /tmp/www; echo signalrail >/tmp/www/index.html; httpd -f -p 8080 -h /tmp/www
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            memory: 64Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        env:
        - name: ROUTE
          value: north
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' repository/manifests/relay.yaml
cd repository
git add manifests
git commit -m "Add station reader"
git remote add origin "$GIT_URL"
git push -u origin main
cd ..
cat > application.yaml <<'DQ_ASSET'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: station
spec:
  project: station
  source:
    repoURL: DQ_GIT_URL
    targetRevision: main
    path: manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: DQ_TARGET_NS
DQ_ASSET
sed -i "s|DQ_GIT_URL|$GIT_URL|g; s|DQ_TARGET_NS|$DQ_NAMESPACE|g" application.yaml
kubectl apply -f application.yaml
cat > patch-4cf3f622c706.json <<'DQ_ASSET'
{
  "operation": {
    "sync": {}
  }
}
DQ_ASSET
jq -e . patch-4cf3f622c706.json >/dev/null
kubectl patch application station --type=merge --patch-file=patch-4cf3f622c706.json
for _ in $(seq 1 90); do
 if kubectl get application station -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null; then break; fi
 sleep 2
done
kubectl get application station -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null

kubectl set env deployment/relay ROUTE=drifted
kubectl rollout status deployment/relay --timeout=90s
kubectl annotate application station argocd.argoproj.io/refresh=hard --overwrite
kubectl wait --for=jsonpath='{.status.sync.status}'=OutOfSync application/station --timeout=60s


source platform.env
python3 -I - <<'STATE'
import json,os,subprocess,yaml
from pathlib import Path
cm={'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'relay-route'},'immutable':True,'data':{'route':'drifted','index.html':'retained-54\n'}}
reader={'apiVersion':'v1','kind':'Pod','metadata':{'name':'retained-reader'},'spec':{
 'securityContext':{'runAsNonRoot':True,'runAsUser':1000,'seccompProfile':{'type':'RuntimeDefault'}},
 'containers':[{'name':'reader','image':os.environ['DQ_APP_IMAGE'],'imagePullPolicy':'Never',
 'command':['httpd','-f','-p','8080','-h','/publication'],
 'resources':{'requests':{'cpu':'10m','memory':'8Mi'},'limits':{'memory':'32Mi'}},
 'securityContext':{'allowPrivilegeEscalation':False,'capabilities':{'drop':['ALL']}},
 'readinessProbe':{'httpGet':{'path':'/','port':8080},'periodSeconds':1},
 'volumeMounts':[{'name':'current','mountPath':'/publication','readOnly':True}]}],
 'volumes':[{'name':'current','configMap':{'name':'relay-route','defaultMode':0o444}}]}}
subprocess.run(['kubectl','apply','-f','-'],input=yaml.safe_dump_all([cm,reader]),text=True,check=True)
subprocess.run(['kubectl','wait','--for=condition=Ready','pod/retained-reader','--timeout=60s'],check=True)
receipts={}
for kind,name in [('application','station'),('deployment','relay'),('configmap','relay-route'),('pod','retained-reader')]:
 obj=json.loads(subprocess.check_output(['kubectl','get',kind,name,'-o','json']));receipts[kind]={'name':name,'uid':obj['metadata']['uid']}
receipts['configmap']['data']=cm['data']
Path('original-handover.json').write_text(json.dumps(receipts,indent=2)+'\n')
cm['data']['route']='north'
Path('repository/manifests/route.yaml').write_text(yaml.safe_dump(cm,sort_keys=False))
p=Path('repository/manifests/relay.yaml');d=yaml.safe_load(p.read_text())
d['spec']['template']['spec']['containers'][0]['env']=[{'name':'ROUTE','valueFrom':{'configMapKeyRef':{'name':'relay-route','key':'route'}}}]
p.write_text(yaml.safe_dump(d,sort_keys=False))
STATE
git -C repository add manifests
git -C repository commit -m 'Publish the in-place handover intent'
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
kubectl patch application station --type merge -p '{"spec":{"ignoreDifferences":[{"group":"apps","kind":"Deployment","name":"relay","jsonPointers":["/spec/template/spec/containers/0/env"]}],"syncPolicy":{"syncOptions":["RespectIgnoreDifferences=true"]}}}'
kubectl annotate application station argocd.argoproj.io/refresh=hard --overwrite

python3 -I - <<'DQ_HANDOVER_RECEIPT'
import json,os,subprocess
from pathlib import Path
original=json.loads(Path('original-handover.json').read_text())
pod=json.loads(subprocess.check_output(['kubectl','get','pod',original['pod']['name'],'-o','json']))
app=json.loads(subprocess.check_output(['kubectl','get','application',original['application']['name'],'-o','json']))
profile={'containers':[{k:c.get(k) for k in ('name','image','command','args','volumeMounts','securityContext')} for c in pod['spec']['containers']],
 'volumes':pod['spec'].get('volumes',[]),'securityContext':pod['spec'].get('securityContext')}
receipt={'original':original,'readerFields':profile,'repoURL':os.environ['GIT_URL'],
 'namespace':os.environ['DQ_NAMESPACE'],'project':app['spec']['project'],'destination':app['spec']['destination'],
 'baselineCommit':Path('release-commit').read_text().strip(),'route':'north',
 'preserveOriginalImmutableMapAndReader':True,'preserveApplicationAndDeploymentIdentity':True,
 'routeUsesNewImmutableConfiguration':True,'managedDeploymentReconcilesFromGit':True,
 'publishedHistoryRetainsBaseline':True,'sourceDirectory':'manifests','sourceBranch':'main',
 'observesCurrentStateOnly':True}
Path('handover-contract.json').write_text(json.dumps(receipt,indent=2)+'\n')
DQ_HANDOVER_RECEIPT

kubectl patch application station --type merge --patch-file=patch-4cf3f622c706.json
for _ in $(seq 1 30); do
 if kubectl get application station -o json | jq -e '.status.operationState.phase=="Failed"' >/dev/null; then break; fi
 sleep 1
done
kubectl get application station -o json | jq -e '.status.operationState.phase=="Failed"' >/dev/null
kubectl get application station -o json | jq '{sync:.status.sync.status,operation:.status.operationState}'
test "$(kubectl exec deployment/relay -c worker -- printenv ROUTE)" = drifted
test "$(kubectl exec retained-reader -- wget -qO- -T 3 http://127.0.0.1:8080)" = retained-54
