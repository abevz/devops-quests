set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
test "$(cat /run/dq/facts/0/initial-throttled)" -ge 10
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get deployment board -o json | jq -e '.spec.replicas==1' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
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
for category,name,expected,marker,label in [('requests', 'cpu', '50m', None, None), ('limits', 'cpu', '50m', None, None), ('requests', 'memory', '8Mi', None, None), ('limits', 'memory', '32Mi', None, None)]:
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
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
# Measure the serving container directly; the player's worksheet cannot supply this evidence.
sample=$(timeout 8s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- sh -c '
read_throttled() {
 while read -r key value rest; do
  if test "$key" = nr_throttled; then printf "%s\n" "$value"; return; fi
 done < /sys/fs/cgroup/cpu.stat
 return 1
}
before=$(read_throttled) || exit 1
sleep 2
after=$(read_throttled) || exit 1
case "$before:$after" in *[!0-9:]*|:*|*:) exit 1;; esac
test "$after" -ge "$before" || exit 1
printf "%s\n" "$((after-before))"
')
if ! [[ "$sample" =~ ^[0-9]+$ ]] || ! test "$sample" -le 5; then exit 1; fi
test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- wget -qO- -T 3 http://board:8080)" = north-94
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get deployment board -o json | jq -e '.status.readyReplicas==1' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
sample=$(bash measure.sh)
if ! [[ "$sample" =~ ^[0-9]+$ ]] || ! test "$sample" -le 5; then printf "Idle sample still throttled: %s\n" "$sample" >&2; exit 1; fi
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080)" = north-94
)
[ $? -eq 0 ] || failed=1
exit "$failed"
