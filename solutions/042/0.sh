set -euo pipefail
cd ~/quest
source platform.env
umask 077
secret=$(mktemp)
trap 'rm -f "$secret"' EXIT
python3 - "$secret" <<'DQ_SECRET'
import base64
import json
import os
import sys

registry = os.environ['REGISTRY']
auth = base64.b64encode((os.environ['REGISTRY_USER'] + ':' + os.environ['REGISTRY_PASSWORD']).encode()).decode()
config = json.dumps({'auths': {registry: {'auth': auth}}}).encode()
secret = {'apiVersion': 'v1', 'kind': 'Secret', 'metadata': {'name': 'registry-pull'}, 'type': 'kubernetes.io/dockerconfigjson', 'data': {'.dockerconfigjson': base64.b64encode(config).decode()}}
with open(sys.argv[1], 'w') as output:
    json.dump(secret, output)
DQ_SECRET
kubectl apply -f "$secret" >/dev/null
kubectl rollout restart deployment/board
kubectl rollout status deployment/board --timeout=90s
