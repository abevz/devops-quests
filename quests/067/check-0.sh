set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
helm get values board -o json | jq -e '(.readinessPort|tonumber)==8080' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
helm history board -o json | jq -e 'length>=3 and .[-1].status=="deployed"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl get deployment board -o jsonpath='{.metadata.uid}')" = "$(cat /run/dq/facts/0/original-deployment-uid)"
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
live=$(kubectl get deployment board -o json 2>/dev/null || true)
rendered=$(helm get manifest board 2>/dev/null || true)
python3 -I - /dev/fd/3 /dev/fd/4 3<<<"$live" 4<<<"$rendered" <<'DQ_READINESS'
import sys

from dq_check import read_argument as _dq_read_argument

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys,math,re

from dq_check import workload_worker as _dq_worker

def worker(document):
    return _dq_worker(document, error="worker")



from dq_check import readiness_probe as readiness
import yaml
try:
    live=json.loads(sys.argv[1])
    rendered=[doc for doc in yaml.safe_load_all(sys.argv[2]) if isinstance(doc,dict) and doc.get("kind")=="Deployment" and doc.get("metadata",{}).get("name")=="board"]
    ok=len(rendered)==1 and readiness(live,tcp=True) and readiness(rendered[0],tcp=True)
except (ValueError,KeyError,TypeError,AttributeError,yaml.YAMLError):
    ok=False
sys.exit(not ok)
DQ_READINESS
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_3]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://127.0.0.1:8080)" = north-67
)
[ $? -eq 0 ] || failed=1
exit "$failed"
