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

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys,math,re

def worker(document):
    items=[c for c in document["spec"]["template"]["spec"]["containers"] if c.get("name")=="worker"]
    if len(items)!=1:raise ValueError("worker")
    return items[0]

def port(container,value):
    if type(value) is int:return value
    if not isinstance(value,str):raise ValueError("port")
    found=[p["containerPort"] for p in container.get("ports",[]) if p.get("name")==value]
    if len(found)!=1 or type(found[0]) is not int:raise ValueError("named port")
    return found[0]

def readiness(document,tcp=False):
    container=worker(document);probe=container.get("readinessProbe",{})
    kinds=[name for name in ("httpGet","tcpSocket","exec","grpc") if probe.get(name) is not None]
    if len(kinds)!=1 or kinds[0] not in (["httpGet","tcpSocket"] if tcp else ["httpGet"]):return False
    action=probe[kinds[0]]
    if action.get("host","")!="":return False
    if kinds[0]=="httpGet" and action.get("scheme","HTTP")!="HTTP":return False
    return port(container,action.get("port"))==8080
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
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_0]'
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
python3 - <<'DQ_HTTP_V3'
import json
import subprocess
import time

command = [
    "kubectl", "exec", "--pod-running-timeout=2s", "deployment/board",
    "-c", "worker", "--", "wget", "-qO-", "-T", "3", "http://board:8080",
]
deadline = time.monotonic() + 4.0
last_body = "<no response observed>"
while True:
    remaining = deadline - time.monotonic()
    if remaining <= 0.1:
        break
    try:
        result = subprocess.run(
            command, capture_output=True, check=False, text=True,
            encoding="utf-8", errors="replace",
            timeout=remaining - 0.1,
        )
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        output = output.rstrip("\n")
        if output:
            last_body = output
    except OSError:
        pass
    else:
        output = result.stdout.rstrip("\n")
        if result.returncode == 0:
            last_body = output or "<empty body>"
            if output == "north-102-v3":
                raise SystemExit(0)
        elif output:
            last_body = output
    remaining = deadline - time.monotonic()
    if remaining <= 0.1:
        break
    time.sleep(min(0.2, remaining))
safe_body = json.dumps(last_body, ensure_ascii=True)
print(f"board:8080 expected north-102-v3; last body: {safe_body}: ✗ [DQ:http_v3]")
raise SystemExit(1)
DQ_HTTP_V3
)
[ $? -eq 0 ] || failed=1
exit "$failed"
