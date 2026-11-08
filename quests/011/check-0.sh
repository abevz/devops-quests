set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
kubectl rollout status deployment/clock --timeout=3s
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
pods=$(kubectl get pods -l app=clock -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 3<<<"$pods" <<'DQ_CLOCK'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,re,subprocess,sys
try:
    pods=json.loads(sys.argv[1])['items']
    current=[p['metadata']['name'] for p in pods if not p.get('metadata',{}).get('deletionTimestamp') and p.get('status',{}).get('phase')=='Running']
except (ValueError,KeyError,TypeError,AttributeError):current=[]
filename='/tmp/identity'
failed=not current
if not current:print('current clock Pods: ✗')
for name in current:
    try:
        result=subprocess.run(['kubectl','exec','--pod-running-timeout=2s',name,'-c','worker','--','cat',filename],capture_output=True,timeout=4)
        matches=(result.stdout.rstrip(b'\n')==name.encode()) if filename=='/tmp/identity' else re.search(rb'(?m)^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$',result.stdout) is not None
        ok=result.returncode==0 and matches
    except (OSError,subprocess.TimeoutExpired,UnicodeError):ok=False
    if not ok:
        failed=True;print('pod/'+name+' '+filename+': ✗')
sys.exit(failed)
DQ_CLOCK
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
pods=$(kubectl get pods -l app=clock -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 3<<<"$pods" <<'DQ_CLOCK'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,re,subprocess,sys
try:
    pods=json.loads(sys.argv[1])['items']
    current=[p['metadata']['name'] for p in pods if not p.get('metadata',{}).get('deletionTimestamp') and p.get('status',{}).get('phase')=='Running']
except (ValueError,KeyError,TypeError,AttributeError):current=[]
filename='/tmp/clock'
failed=not current
if not current:print('current clock Pods: ✗')
for name in current:
    try:
        result=subprocess.run(['kubectl','exec','--pod-running-timeout=2s',name,'-c','worker','--','cat',filename],capture_output=True,timeout=4)
        matches=(result.stdout.rstrip(b'\n')==name.encode()) if filename=='/tmp/identity' else re.search(rb'(?m)^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$',result.stdout) is not None
        ok=result.returncode==0 and matches
    except (OSError,subprocess.TimeoutExpired,UnicodeError):ok=False
    if not ok:
        failed=True;print('pod/'+name+' '+filename+': ✗')
sys.exit(failed)
DQ_CLOCK
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
exit "$failed"
