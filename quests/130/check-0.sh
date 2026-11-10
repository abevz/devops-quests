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
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

def get(kind, name=None):
    args=['kubectl','get',kind]+([name] if name else [])+['-o','json']
    return json.loads(subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=3))

from dq_check import named as _dq_named

def named(items, name):
    return _dq_named(items, name, error="named identity")

from dq_check import workload_worker as _dq_worker

def worker(document):
    return _dq_worker(document, error="named identity", ignore_non_mappings=True)

from dq_check import quantity as _dq_quantity

def quantity(value):
    return _dq_quantity(value, dialect='coerced_ascii')

def require(good, marker):
    if not good:raise AssertionError(marker)

try:
    try:d=get('deployment','board')
    except Exception:d={}
    try:resources=worker(d).get('resources',{})
    except Exception:resources={}
    try:request=quantity(resources.get('requests',{}).get('cpu','0'))
    except Exception:request=None
    try:limit=quantity(resources.get('limits',{}).get('cpu','0'))
    except Exception:limit=None
    checks=[('request',request is not None and request>0 and limit is not None and request<=limit),('limit',limit is not None and 0<limit<=Decimal('0.2')),('ready',d.get('status',{}).get('readyReplicas')==2)]
    failed=False
    for marker,good in checks:
        if not good:print('Required scaling result is missing: ✗ [DQ:'+marker+']');failed=True
    if failed:raise SystemExit(1)
except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'request'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_0]'
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

try:
    try:d=get('hpa','board')
    except Exception:d={}
    spec=d.get('spec',{});status=d.get('status',{});target=spec.get('scaleTargetRef',{})
    metrics=[m.get('resource',{}) for m in spec.get('metrics',[]) if m.get('type')=='Resource' and m.get('resource',{}).get('name')=='cpu']
    checks=[('minimum',spec.get('minReplicas',1)==1 and bool(spec)),('maximum',spec.get('maxReplicas')==2),('target',target.get('apiVersion')=='apps/v1' and target.get('kind')=='Deployment' and target.get('name')=='board' and len(metrics)==1 and metrics[0].get('target',{}).get('type')=='Utilization' and metrics[0]['target'].get('averageUtilization')==50),('current',status.get('currentReplicas')==2),('desired',status.get('desiredReplicas')==2),('metric',any(m.get('type')=='Resource' and m.get('resource',{}).get('name')=='cpu' and type(m['resource'].get('current',{}).get('averageUtilization')) is int and m['resource']['current']['averageUtilization']>50 for m in status.get('currentMetrics',[])))]
    failed=False
    for marker,good in checks:
        if not good:print('Required scaling result is missing: ✗ [DQ:'+marker+']');failed=True
    if failed:raise SystemExit(1)
except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'target'
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
