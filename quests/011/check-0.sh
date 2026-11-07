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
)
[ $? -eq 0 ] || failed=1
(
set -e
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
)
[ $? -eq 0 ] || failed=1
exit "$failed"
