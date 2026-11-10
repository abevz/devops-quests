set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
set -euo pipefail
cd ~/quest
kubectl rollout status deployment/board --timeout=3s
set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

def get(kind, name=None):
    args=['kubectl','get',kind]+([name] if name else [])+['-o','json']
    return json.loads(subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=3))

def scaled(value,count,up):
    if type(value) is int:
        if value<0:raise ValueError('budget')
        return value
    if not isinstance(value,str) or not re.fullmatch(r'[0-9]+%',value):raise ValueError('budget')
    value=int(value[:-1])*count
    return (value+99)//100 if up else value//100

def require(good, marker):
    if not good:raise AssertionError(marker)

try:
    d=get('deployment','board');s=d['spec'];rolling=s.get('strategy',{}).get('rollingUpdate',{})
    require(s.get('replicas')==2 and d.get('status',{}).get('availableReplicas')==2,'available')
    require(s.get('strategy',{}).get('type')=='RollingUpdate' and scaled(rolling.get('maxSurge','25%'),2,True)==1 and scaled(rolling.get('maxUnavailable','25%'),2,False)==0,'strategy')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'strategy'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
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

def require(good, marker):
    if not good:raise AssertionError(marker)

from dq_check import port_number as port_number

try:
    service=get('service','board')['spec'];d=get('deployment','board');labels=d['spec']['template']['metadata']['labels']
    selector=service.get('selector',{})
    require(selector.get('app')=='board' and all(labels.get(k)==v for k,v in selector.items()),'service')
    ports=[p for p in service.get('ports',[]) if p.get('port')==8080 and p.get('protocol','TCP')=='TCP']
    require(len(ports)==1 and port_number(d['spec']['template']['spec']['containers'],ports[0].get('targetPort',8080))==8080,'service')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'service'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_1]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
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

def require(good, marker):
    if not good:raise AssertionError(marker)

from dq_check import current_pods

try:
    d=get('deployment','board');pods=current_pods(d,get('replicasets'),get('pods'));pods=[p for p in pods if p.get('status',{}).get('phase')=='Running']
    require(bool(pods),'http')
    for pod in pods:
        value=subprocess.check_output(['kubectl','exec','--pod-running-timeout=2s',pod['metadata']['name'],'-c','worker','--','wget','-qO-','-T','3','http://board:8080'],stderr=subprocess.DEVNULL,timeout=4)
        require(value.rstrip(b'\n')==b'north-40','http')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'http'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_2]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
