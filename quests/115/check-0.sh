set -euo pipefail
cd ~/quest
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
set -euo pipefail
cd ~/quest
failed=0
selector_ok() {
  python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 /dev/fd/6 3<<<"$1" 4<<<"$pods" 5<<<"$2" 6<<<"$3" <<'DQ_SELECTOR'
import sys

from dq_check import read_argument as _dq_read_argument

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys
try:
    service,pods=json.loads(sys.argv[1]),json.loads(sys.argv[2])['items'];key,value=sys.argv[3:5]
    selector=service['spec']['selector']
    intended=[p for p in pods if p['metadata'].get('labels',{}).get(key)==value and not p['metadata'].get('deletionTimestamp')]
    from dq_check import selector_matches as _dq_matches

    def matches(p):
        return all(_dq_matches(p["metadata"].get("labels", {}), {"matchLabels": {k: v}}, dialect="pdb") for k, v in selector.items())
    ok=isinstance(selector,dict) and selector.get(key)==value and bool(intended) and all(matches(p) for p in intended) and all(not matches(p) or p['metadata'].get('labels',{}).get(key)==value for p in pods)
except (ValueError,KeyError,TypeError,AttributeError):ok=False
sys.exit(not ok)
DQ_SELECTOR
}
pods=$(timeout 2s kubectl get pods -o json 2>/dev/null || true)
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
service=$(timeout 2s kubectl get service board -o json 2>/dev/null || true)
if ! selector_ok "$service" app green; then printf '%s\n' 'service selector retains only the supplied green workload: ✗ [DQ:selector]'; failed=1; fi
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = green-115; then printf '%s\n' 'board:8080 = green-115: ✗ [DQ:http]'; failed=1; fi
exit "$failed"
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
