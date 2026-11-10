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
quota=$(timeout 2s kubectl get resourcequota station -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 3<<<"$quota" <<'DQ_QUOTA'
import sys

from dq_check import read_argument as _dq_read_argument

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,re,sys
from decimal import Decimal, InvalidOperation

from dq_check import quantity as _dq_quantity

def quantity(value):
    return _dq_quantity(value, dialect="typed_ascii")

def equal(value,expected):
    try:return quantity(value)==quantity(expected)
    except (ValueError,TypeError,InvalidOperation,OverflowError):return False

def emit(marker,label,ok):
    global failed
    if not ok:
        failed=True;print(label+": ✗ [DQ:"+marker+"]")

def doc(value):
    try:
        result=json.loads(value)
        return result if isinstance(result,dict) else {}
    except ValueError:return {}

from dq_check import optional_pod_worker as worker

failed=False
quota=doc(sys.argv[1]);hard=quota.get('spec',{}).get('hard',{})
expected={'requests.cpu':'200m','limits.cpu':'400m','requests.memory':'32Mi','limits.memory':'64Mi','pods':'2'}
emit('quota','ResourceQuota station hard = supplied budget',all(equal(hard.get(key),value) for key,value in expected.items()))
sys.exit(failed)
DQ_QUOTA
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
limits=$(timeout 2s kubectl get limitrange defaults -o json 2>/dev/null || true)
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 /dev/fd/4 3<<<"$limits" 4<<<"$board" <<'DQ_DEFAULTS'
import sys

from dq_check import read_argument as _dq_read_argument

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,re,sys
from decimal import Decimal, InvalidOperation

from dq_check import quantity as _dq_quantity

def quantity(value):
    return _dq_quantity(value, dialect="typed_ascii")

def equal(value,expected):
    try:return quantity(value)==quantity(expected)
    except (ValueError,TypeError,InvalidOperation,OverflowError):return False

def emit(marker,label,ok):
    global failed
    if not ok:
        failed=True;print(label+": ✗ [DQ:"+marker+"]")

def doc(value):
    try:
        result=json.loads(value)
        return result if isinstance(result,dict) else {}
    except ValueError:return {}

from dq_check import optional_pod_worker as worker

failed=False
limits=doc(sys.argv[1]);board=doc(sys.argv[2]);items=[x for x in limits.get('spec',{}).get('limits',[]) if x.get('type')=='Container']
container=worker(board.get('spec',{}).get('template',{}))
# The API allows one Container entry; duplicates must not allow contradictory defaults.
emit('default','LimitRange defaults default.cpu = 200m',bool(items) and all(equal(x.get('default',{}).get('cpu'),'200m') for x in items))
emit('request','LimitRange defaults defaultRequest.cpu = 100m',bool(items) and all(equal(x.get('defaultRequest',{}).get('cpu'),'100m') for x in items))
emit('template','board worker resources = empty',bool(container) and (container.get('resources') or {})=={})
sys.exit(failed)
DQ_DEFAULTS
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
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
pods=$(timeout 2s kubectl get pods -l app=board -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 /dev/fd/4 3<<<"$board" 4<<<"$pods" <<'DQ_ADMITTED'
import sys

from dq_check import read_argument as _dq_read_argument

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,re,sys
from decimal import Decimal, InvalidOperation

from dq_check import quantity as _dq_quantity

def quantity(value):
    return _dq_quantity(value, dialect="typed_ascii")

def equal(value,expected):
    try:return quantity(value)==quantity(expected)
    except (ValueError,TypeError,InvalidOperation,OverflowError):return False

def emit(marker,label,ok):
    global failed
    if not ok:
        failed=True;print(label+": ✗ [DQ:"+marker+"]")

def doc(value):
    try:
        result=json.loads(value)
        return result if isinstance(result,dict) else {}
    except ValueError:return {}

from dq_check import optional_pod_worker as worker

failed=False
board=doc(sys.argv[1]);pods=doc(sys.argv[2]);eligible=[p for p in pods.get('items',[]) if not p.get('metadata',{}).get('deletionTimestamp')]
def request(p):
    r=worker(p).get('resources',{}).get('requests',{})
    return equal(r.get('cpu'),'100m') and equal(r.get('memory'),'16Mi')
def limit(p):
    r=worker(p).get('resources',{}).get('limits',{})
    return equal(r.get('cpu'),'200m') and equal(r.get('memory'),'32Mi')
def ready(p):return bool(worker(p)) and any(c.get('name')=='worker' and c.get('ready') is True for c in p.get('status',{}).get('containerStatuses',[]))
emit('ready','deployment board readyReplicas = 1',board.get('status',{}).get('readyReplicas')==1)
emit('pod_requests','non-terminating board worker requests = CPU 100m, memory 16Mi',any(request(p) for p in eligible))
emit('pod_limits','non-terminating board worker limits = CPU 200m, memory 32Mi',any(limit(p) for p in eligible))
emit('pod_ready','non-terminating board Pod has a ready worker',any(ready(p) for p in eligible))
emit('same_pod','one non-terminating Pod has required worker resources and readiness',any(request(p) and limit(p) and ready(p) for p in eligible))
sys.exit(failed)
DQ_ADMITTED
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_2]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-126; then printf '%s\n' 'board:8080 = north-126: ✗ [DQ:http]'; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
