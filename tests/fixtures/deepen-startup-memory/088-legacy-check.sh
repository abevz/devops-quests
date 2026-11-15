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
document=$(kubectl get deployment relay -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 3<<<"$document" <<'DQ_QUANTITY'
import json, sys
from decimal import InvalidOperation
from dq_check import quantity, read_argument, workload_worker as worker

sys.argv = [read_argument(value) for value in sys.argv]

try:
    resources=worker(json.loads(sys.argv[1])).get("resources",{})
except (KeyError,ValueError,TypeError,AttributeError):
    resources={}
failed=False
for category,name,expected,marker,label in [('limits', 'memory', '96Mi', None, None)]:
    try:
        ok=quantity(resources.get(category,{}).get(name), dialect="typed_ascii")==quantity(expected, dialect="typed_ascii")
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
kubectl rollout status deployment/relay --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
