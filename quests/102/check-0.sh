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
board=$(kubectl get deployment board -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 3<<<"$board" <<'DQ_ROLLING'
import sys

from dq_check import read_argument as _dq_read_argument

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys,math,re

from dq_check import workload_worker as _dq_worker

def worker(document):
    return _dq_worker(document, error="worker")



from dq_check import readiness_probe as readiness
def scaled(value,count,up):
    if type(value) is int:
        if value<0:raise ValueError("negative budget")
        return value
    if not isinstance(value,str) or not re.fullmatch(r"[0-9]+%",value):raise ValueError("rolling budget")
    numerator=int(value[:-1])*count
    return (numerator+99)//100 if up else numerator//100

try:document=json.loads(sys.argv[1])
except ValueError:document={}
if not isinstance(document,dict):document={}
spec=document.get("spec",{})
if not isinstance(spec,dict):spec={}
strategy=spec.get("strategy",{})
if not isinstance(strategy,dict):strategy={}
failed=False
checks=[]
checks.append(("strategy","deployment/board strategy = RollingUpdate",strategy.get("type")=="RollingUpdate"))
try:
    spec=document["spec"];count=spec.get("replicas",1)
    if type(count) is not int or count<1:raise ValueError("replicas")
    rolling=spec.get("strategy",{}).get("rollingUpdate",{})
    surge=scaled(rolling.get("maxSurge","25%"),count,True)
    unavailable=scaled(rolling.get("maxUnavailable","25%"),count,False)
    # With zero allowed unavailability a replacement must have positive surge.
    rolling_ok=surge==1 and unavailable==0
except (ValueError,KeyError,TypeError,AttributeError):rolling_ok=False
checks.append(("rolling","deployment/board replacement budget = at most one extra, no unavailability",rolling_ok))
try:healthy=readiness(document)
except (ValueError,KeyError,TypeError,AttributeError):healthy=False
checks.append(("readiness","worker readiness reaches its HTTP listener",healthy))
for marker,label,ok in checks:
    if not ok:failed=True;print(label+": ✗ [DQ:"+marker+"]")
sys.exit(failed)
DQ_ROLLING
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
set -euo pipefail
cd ~/quest
failed=0
board=$(kubectl get deployment board -o json 2>/dev/null || true)
uid=$(cat /run/dq/facts/0/original-deployment-uid 2>/dev/null || true)
check() { local label=$1 expression=$2; if ! jq -e --arg uid "$uid" "$expression" <<<"$board" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
if ! test -n "$uid"; then printf '%s\n' 'original-deployment-uid exists: ✗ [DQ:uid_file]'; failed=1; fi
check 'deployment/board UID = original-deployment-uid [DQ:uid]' '.metadata.uid==$uid'
check 'deployment/board replicas = 2 [DQ:replicas]' '.spec.replicas==2'
check 'deployment/board readyReplicas = 2 [DQ:ready]' '.status.readyReplicas==2'
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-102; then printf '%s\n' 'board:8080 = north-102: ✗ [DQ:http_v1]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
