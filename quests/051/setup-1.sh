set -euo pipefail
cat > backup.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backup
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backup
  template:
    metadata:
      labels:
        app: backup
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
          value: retired
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' backup.yaml
kubectl apply -f backup.yaml

python3 -I - <<'DQ_FAILOVER'
import json,subprocess
from pathlib import Path
facts=json.loads(Path("/run/dq/facts/0/progressive-identities.json").read_text());contract=facts["contract"]
def get(kind,name):return json.loads(subprocess.run(["kubectl","get",kind,name,"-o","json"],capture_output=True,text=True,check=True).stdout)
service=get("service",contract["publicService"]["name"]);producer=get("deployment",contract["producer"]["deployment"]);backup=get("deployment",contract["consumer"]["deployment"])
ports=[p for p in service["spec"]["ports"] if p["port"]==contract["publicService"]["port"] and p.get("protocol","TCP")=="TCP"];assert len(ports)==1
port=ports[0].get("targetPort",ports[0]["port"])
if isinstance(port,str):
    slices=json.loads(subprocess.run(["kubectl","get","endpointslices","-l","kubernetes.io/service-name="+contract["publicService"]["name"],"-o","json"],capture_output=True,text=True,check=True).stdout)["items"]
    resolved={p["port"] for item in slices if any(o.get("kind")=="Service" and o.get("uid")==service["metadata"]["uid"] for o in item.get("metadata",{}).get("ownerReferences",[])) and any(e.get("conditions",{}).get("ready") is not False for e in item.get("endpoints",[])) for p in item.get("ports",[]) if (p.get("name") or "")== (ports[0].get("name") or "") and p.get("protocol","TCP")=="TCP"}
    assert len(resolved)==1
    port=resolved.pop()
assert type(port) is int
Path("failover-identities.json").write_text(json.dumps({"service_uid":service["metadata"]["uid"],"consumer_uid":backup["metadata"]["uid"],"producer_port":port},indent=2)+"\n")
DQ_FAILOVER
rm backup.yaml
