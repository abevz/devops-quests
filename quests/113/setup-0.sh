set -euo pipefail
cd ~/quest
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
        - sh
        - -c
        - mkdir -p /tmp/site; printf "%s\n" "north-113" > /tmp/site/index.html; exec httpd -f -p 8080
          -h /tmp/site
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
      terminationGracePeriodSeconds: 1
DQ_ASSET
python3 - client.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f client.yaml
kubectl rollout status deployment/board --timeout=90s
kubectl rollout status deployment/client --timeout=90s
source book-components.env
cat > gateway.yaml <<'DQ_ASSET'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: station
spec:
  gatewayClassName: __GATEWAY_CLASS__
  listeners:
  - name: web
    hostname: north.station.internal
    protocol: HTTP
    port: 8000
    allowedRoutes:
      namespaces:
        from: Same
DQ_ASSET
python3 - gateway.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
sed -i "s/__GATEWAY_CLASS__/$GATEWAY_CLASS/g" gateway.yaml
kubectl apply -f gateway.yaml
printf '{"class":"%s","url":"%s"}
' "$GATEWAY_CLASS" "$GATEWAY_URL" > gateway-target.json
cat > route.yaml <<'DQ_ASSET'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: board
spec:
  parentRefs:
  - name: station
    sectionName: retired
  hostnames:
  - north.station.internal
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: board
      port: 8099
DQ_ASSET
python3 - route.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f route.yaml
for i in $(seq 1 30); do
 if kubectl get httproute board -o json | jq -e '.metadata.generation as $g | any(.status.parents[]?.conditions[]?; .type=="Accepted" and .status=="False" and .observedGeneration==$g)' >/dev/null; then break; fi
 sleep 1
done
python3 -I - <<'DQ_ATTACHMENT_SEED'
import json,subprocess
from pathlib import Path
def get(kind,name):
    return json.loads(subprocess.check_output(['kubectl','get',kind,name,'-o','json'],text=True))
def deployments(names):
    result={}
    for name in names:
        value=get('deployment',name)
        result[name]={'uid':value['metadata']['uid'],
                      'image':next(item['image'] for item in value['spec']['template']['spec']['containers'] if item['name']=='worker')}
    return result

gateway=get('gateway','station')
route=get('httproute','board')
assert any(condition.get('type')=='Accepted' and condition.get('status')=='False' and condition.get('observedGeneration')==route['metadata']['generation'] for parent in route.get('status',{}).get('parents',[]) for condition in parent.get('conditions',[]))
contract={'schema':1,'gateway':'station','route':'board','backendService':'board',
          'preserveExistingGatewayRouteServiceAndWorkloads':True,
          'preserveGatewayListenerDefinitions':True,'preserveProvidedWorkerImages':True,
          'currentParentStatusForCurrentRouteGeneration':True,'observesCurrentStateOnly':True}
controllers={item['controllerName'] for item in route.get('status',{}).get('parents',[]) if item.get('controllerName')}
assert len(controllers)==1
facts={'contract':contract,'gatewayUID':gateway['metadata']['uid'],'routeUID':route['metadata']['uid'],
       'serviceUID':get('service','board')['metadata']['uid'],'listeners':gateway['spec']['listeners'],
       'controller':next(iter(controllers)),'deployments':deployments(['board','client'])}
Path('attachment-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
Path('attachment-identities.json').write_text(json.dumps(facts)+'\n')
DQ_ATTACHMENT_SEED
rm -f board.yaml service.yaml client.yaml gateway.yaml route.yaml book-components.env
