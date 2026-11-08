set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
kubectl get deployment board -o json | jq -e ' .spec.replicas==1' >/dev/null
)
[ $? -eq 0 ] || failed=1
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
for category,name,expected,marker,label in [('requests', 'cpu', '100m', None, None), ('limits', 'cpu', '300m', None, None)]:
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
for category,name,expected,marker,label in [('requests', 'memory', '16Mi', None, None), ('limits', 'memory', '64Mi', None, None)]:
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
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_2]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/board --timeout=3s
)
[ $? -eq 0 ] || failed=1
(
set -e
pod=$(kubectl get pods -l app=board -o jsonpath='{.items[0].metadata.name}')
test "$(kubectl exec "$pod" -c worker -- wget -qO- http://127.0.0.1:8080)" = north
)
[ $? -eq 0 ] || failed=1
exit "$failed"
