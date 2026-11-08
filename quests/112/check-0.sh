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
document=$(kubectl get deployment board -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 3<<<"$document" <<'DQ_QUANTITY'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,re,sys
from decimal import Decimal, InvalidOperation

def quantity(value):
    if isinstance(value,bool) or not isinstance(value,(str,int,float)):
        raise ValueError("quantity type")
    match=re.fullmatch(r"([+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)([numkKMGTPE]|[KMGTPE]i)?",str(value))
    if not match:
        raise ValueError("quantity syntax")
    number,suffix=match.groups()
    scales={"":Decimal(1),"n":Decimal("1e-9"),"u":Decimal("1e-6"),"m":Decimal("1e-3"),"k":Decimal("1e3"),"K":Decimal("1e3")}
    for index,letter in enumerate("MGTPE",2):
        scales[letter]=Decimal(1000)**index
    for index,letter in enumerate("KMGTPE",1):
        scales[letter+"i"]=Decimal(1024)**index
    return Decimal(number)*scales[suffix or ""]

def worker(document):
    containers=document["spec"]["template"]["spec"]["containers"]
    matches=[c for c in containers if c.get("name")=="worker"]
    if len(matches)!=1:
        raise ValueError("worker identity")
    return matches[0]

try:
    resources=worker(json.loads(sys.argv[1])).get("resources",{})
except (KeyError,ValueError,TypeError,AttributeError):
    resources={}
failed=False
for category,name,expected,marker,label in [('requests', 'cpu', '100m', 'request', 'board CPU request = 100m'), ('limits', 'cpu', '200m', 'limit', 'board CPU limit = 200m')]:
    try:
        ok=quantity(resources.get(category,{}).get(name))==quantity(expected)
    except (KeyError,ValueError,TypeError,AttributeError,InvalidOperation,OverflowError):
        ok=False
    if not ok:
        failed=True
        if marker:
            print(label+": ✗ [DQ:"+marker+"]")
sys.exit(failed)
DQ_QUANTITY
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
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
hpa=$(timeout 2s kubectl get hpa board -o json 2>/dev/null || true)
check minimum 'HPA minReplicas = 1' '.spec.minReplicas==1' "$hpa"
check maximum 'HPA maxReplicas = 2' '.spec.maxReplicas==2' "$hpa"
check target 'HPA CPU target utilization = 50' '[.spec.metrics[]? | select((.type=="Resource" and .resource.name=="cpu") or (.type=="ContainerResource" and .containerResource.name=="cpu" and .containerResource.container=="worker")) | (.resource//.containerResource)] as $cpu | ($cpu|length)>0 and all($cpu[]; .target.type=="Utilization" and (.target.averageUtilization|type)=="number" and .target.averageUtilization>0) and ([$cpu[].target.averageUtilization]|min)==50' "$hpa"
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
hpa=$(timeout 2s kubectl get hpa board -o json 2>/dev/null || true)
check ready 'board readyReplicas = 2' '.status.readyReplicas==2' "$board"
check current 'HPA currentReplicas = 2' '.status.currentReplicas==2' "$hpa"
check desired 'HPA desiredReplicas = 2' '.status.desiredReplicas==2' "$hpa"
check metric 'HPA current CPU utilization > 50' 'any(.status.currentMetrics[]?; select((.type=="Resource" and .resource.name=="cpu") or (.type=="ContainerResource" and .containerResource.name=="cpu" and .containerResource.container=="worker")) | (.resource//.containerResource) | (.current.averageUtilization|type)=="number" and .current.averageUtilization>50)' "$hpa"
check active 'HPA ScalingActive = True' 'any(.status.conditions[]?;.type=="ScalingActive" and .status=="True")' "$hpa"
if ! timeout 2s kubectl top pods -l app=board --no-headers 2>/dev/null | grep -E '[0-9]+m' >/dev/null; then printf '%s\n' 'kubectl top pods shows CPU millicores: ✗ [DQ:top]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
hpa=$(timeout 2s kubectl get hpa board -o json 2>/dev/null || true)
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-112; then printf '%s\n' 'board:8080 = north-112: ✗ [DQ:http]'; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
