set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.spec.source.repoURL==$url and (.spec.source.path | (startswith("/")|not) and ([splits("/") | select(.!="" and .!=".")]==["manifests"])) and .spec.source.targetRevision=="main" and .status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

def get(kind, name=None):
    args=['kubectl','get',kind]+([name] if name else [])+['-o','json']
    return json.loads(subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=3))

def named(items, name):
    found=[x for x in items or [] if isinstance(x,dict) and x.get('name')==name]
    if len(found)!=1:raise ValueError('named identity')
    return found[0]

def worker(document):return named(document['spec']['template']['spec']['containers'],'worker')

def require(good, marker):
    if not good:raise AssertionError(marker)

try:
    d=get('deployment','board');w=worker(d);variable=named(w.get('env',[]),'ROUTE_SECRET')
    reference=variable.get('valueFrom',{}).get('secretKeyRef',{})
    require('value' not in variable and set(variable.get('valueFrom',{}))=={'secretKeyRef'} and reference.get('name')=='route-secret' and reference.get('key')=='value','board_env')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'board_env'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
test "$(kubectl get secret route-secret -o jsonpath='{.data.value}' | base64 -d)" = north-secret
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" -H 'Content-Type: application/json' --request POST --data '{"paths":["secret/data/dispatch","secret/data/unrelated","sys/mounts"]}' "$VAULT_ADDR/v1/sys/capabilities-self" | jq -e '."secret/data/dispatch"==["read"] and ."secret/data/unrelated"==["deny"] and ."sys/mounts"==["deny"]' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
test "$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080)" = north-70
)
[ $? -eq 0 ] || failed=1
exit "$failed"
