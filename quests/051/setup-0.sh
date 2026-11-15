set -euo pipefail
cat > deployment.yaml <<'DQ_ASSET'
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
        readinessProbe:
          httpGet:
            port: 9090
            path: /
          periodSeconds: 2
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' deployment.yaml
kubectl apply -f deployment.yaml

python3 -I - <<'DQ_PUBLICATION'
import json,secrets,subprocess
from pathlib import Path
producer_id=secrets.token_hex(16)
contract={"producer":{"deployment":"relay","sourceConfigMap":"relay-source"},"consumer":{"deployment":"backup"},"publicService":{"name":"relay-gateway","port":8080,"type":"ClusterIP"},"producerPath":"/release.json","consumerPath":"/consumer.json","publicationSchema":{"producer_id":"string","route":"string"},"consumerEnvironment":["ROUTE","PRODUCER_ID"]}
data={"ROUTE":"north","PRODUCER_ID":producer_id,"index.html":"signalrail\n","release.json":json.dumps({"producer_id":producer_id,"route":"north"})+"\n"}
cm={"apiVersion":"v1","kind":"ConfigMap","metadata":{"name":contract["producer"]["sourceConfigMap"]},"data":data}
subprocess.run(["kubectl","apply","-f","-"],input=json.dumps(cm),text=True,check=True)
def get(kind,name):return json.loads(subprocess.run(["kubectl","get",kind,name,"-o","json"],capture_output=True,text=True,check=True).stdout)
cm=get("configmap",cm["metadata"]["name"]);producer=get("deployment",contract["producer"]["deployment"])
Path("progressive-contract.json").write_text(json.dumps(contract,indent=2)+"\n")
Path("progressive-identities.json").write_text(json.dumps({"contract":contract,"producer_uid":producer["metadata"]["uid"],"source_uid":cm["metadata"]["uid"],"data":cm["data"]},indent=2)+"\n")
DQ_PUBLICATION
rm deployment.yaml
