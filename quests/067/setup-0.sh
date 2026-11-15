set -euo pipefail
cd ~/quest
mkdir -p chart/templates
python3 -I - <<'DQ_HELM_SEED'
import json,os,secrets,yaml
from pathlib import Path
Path('chart/Chart.yaml').write_text('apiVersion: v2\nname: station-board\nversion: 0.1.0\n')
Path('chart/templates/board.yaml').write_text("apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: board\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: board\n  template:\n    metadata:\n      labels:\n        app: board\n    spec:\n      securityContext:\n        runAsNonRoot: true\n        runAsUser: 1000\n        runAsGroup: 1000\n        fsGroup: 1000\n        seccompProfile:\n          type: RuntimeDefault\n      containers:\n      - name: worker\n        image: '{{ .Values.image }}'\n        imagePullPolicy: Never\n        command:\n        - httpd\n        - -f\n        - -p\n        - '8080'\n        - -h\n        - /srv/board\n        resources:\n          requests:\n            cpu: 10m\n            memory: 8Mi\n          limits:\n            cpu: 200m\n            memory: 32Mi\n        securityContext:\n          allowPrivilegeEscalation: false\n          capabilities:\n            drop:\n            - ALL\n        readinessProbe:\n          httpGet:\n            path: /\n            port: {{ .Values.readinessPort }}\n          initialDelaySeconds: 1\n          periodSeconds: 1\n        ports:\n        - name: http\n          containerPort: 8080\n        volumeMounts:\n        - name: bundle\n          mountPath: /srv/board\n          readOnly: true\n      volumes:\n      - name: bundle\n        configMap:\n          name: board-data\n")
Path('chart/templates/service.yaml').write_text('apiVersion: v1\nkind: Service\nmetadata:\n  name: board\nspec:\n  selector:\n    app: board\n  ports:\n  - port: 8080\n    targetPort: http\n')
Path('chart/templates/bundle.yaml').write_text('apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: board-data\ndata:\n  index.html: "north-67\\n"\n  release.json: {{ dict "release_id" .Values.releaseId "route" "north-67" | toJson | quote }}\n')
Path('chart/values.yaml').write_text(yaml.safe_dump({'image':os.environ['DQ_APP_IMAGE'],'readinessPort':8080,'releaseId':secrets.token_hex(16)},sort_keys=False))
DQ_HELM_SEED
helm install board ./chart --wait --timeout=90s
python3 -I - <<'DQ_HELM_FACTS'
import json,subprocess
from pathlib import Path
from dq_check import workload_worker
def get(kind,name):return json.loads(subprocess.run(['kubectl','get',kind,name,'-o','json'],capture_output=True,text=True,check=True).stdout)
deployment=get('deployment','board');cm=get('configmap','board-data');service=get('service','board')
record=json.loads(cm['data']['release.json'])
Path('original-deployment-uid').write_text(deployment['metadata']['uid'])
facts={'deployment_uid':deployment['metadata']['uid'],'source_uid':cm['metadata']['uid'],'service_uid':service['metadata']['uid'],'release_id':record['release_id'],'image':workload_worker(deployment)['image']}
Path('helm-identities.json').write_text(json.dumps(facts,indent=2)+'\n')
DQ_HELM_FACTS
helm upgrade board ./chart --reuse-values --set readinessPort=9090
python3 -I - <<'DQ_HELM_EVOLUTION'
import json,yaml
from pathlib import Path
Path('chart/Chart.yaml').write_text('apiVersion: v2\nname: station-board\nversion: 0.2.0\n')
p=Path('chart/values.yaml');values=yaml.safe_load(p.read_text());values['routeMessage']='north-67';p.write_text(yaml.safe_dump(values,sort_keys=False))
Path('chart/values.schema.json').write_text(json.dumps({'type': 'object', 'required': ['image', 'readinessPort', 'releaseId', 'routeMessage'], 'properties': {'image': {'type': 'string', 'minLength': 1}, 'releaseId': {'type': 'string', 'pattern': '^[a-f0-9]{32}$'}, 'readinessPort': {'anyOf': [{'type': 'integer', 'minimum': 1, 'maximum': 65535}, {'type': 'string', 'pattern': '^[0-9]+$'}]}, 'routeMessage': {'type': 'string', 'minLength': 1}}, 'additionalProperties': True},indent=2)+'\n')
Path('helm-contract.json').write_text(json.dumps({'release': 'board', 'deployment': 'board', 'configMap': 'board-data', 'service': 'board', 'servicePort': 8080, 'response': 'north-67', 'metadataPath': '/release.json', 'metadataSchema': {'release_id': 'string', 'route': 'string'}, 'renderCases': [{'readinessPort': 8080, 'routeMessage': 'north-67'}, {'readinessPort': 8081, 'routeMessage': 'canary-67'}]},indent=2)+'\n')
DQ_HELM_EVOLUTION
rm chart/templates/bundle.yaml chart/templates/service.yaml
