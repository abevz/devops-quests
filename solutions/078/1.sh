set -euo pipefail
cd ~/quest
source platform.env
python3 -I - <<'PRIVATE_PULL' | kubectl apply -f - >/dev/null
import base64,json,os
auth=base64.b64encode((os.environ['REGISTRY_USER']+':'+os.environ['REGISTRY_PASSWORD']).encode()).decode()
config={'auths':{os.environ['REGISTRY']:{'auth':auth}}}
document={'apiVersion':'v1','kind':'Secret','metadata':{'name':'registry-pull'},'type':'kubernetes.io/dockerconfigjson',
'data':{'.dockerconfigjson':base64.b64encode(json.dumps(config).encode()).decode()}}
print(json.dumps(document))
PRIVATE_PULL
kubectl scale deployment board --replicas=1
kubectl rollout status deployment/board --timeout=90s
