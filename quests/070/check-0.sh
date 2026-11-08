set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" '(.spec.source.path | (startswith("/")|not) and ([splits("/") | select(.!="" and .!=".")]==["manifests"])) and .status.sync.status=="Synced" and .status.sync.revision==$rev' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
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
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_1]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
