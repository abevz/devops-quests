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
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
document=$(kubectl get deployment board -o json 2>/dev/null || true)
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
for category,name,expected,marker,label in [('requests', 'cpu', '50m', None, None), ('limits', 'cpu', '50m', None, None), ('requests', 'memory', '8Mi', None, None), ('limits', 'memory', '32Mi', None, None)]:
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
