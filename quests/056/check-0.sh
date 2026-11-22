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
for bad in 0 4 1.5; do if tofu plan -input=false -var="replicas=$bad" >/dev/null 2>&1; then exit 1; fi; done
python3 -I - <<'DQ_CAPACITY'
import json,subprocess,sys
from pathlib import Path
contract=json.loads(Path('/run/dq/facts/0/capacity-contract.json').read_text())
for category in ('accept','reject'):
    for case in contract[category]:
        result=subprocess.run(['tofu','plan','-input=false','-refresh=false','-no-color','-var=replicas='+str(case['replicas']),'-var=pool='+json.dumps(case['pool'])],capture_output=True,text=True)
        accepted=result.returncode==0
        if accepted != (category=='accept'):
            print('Valid requests must plan and unsafe requests must be rejected: ✗ [DQ:capacity_contract]')
            sys.exit(1)
DQ_CAPACITY
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
set +e
(
set -e
test "$(cat replicas.txt)" = 2
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The applied replica file could not be verified: ✗ [DQ:capacity_file]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
tofu plan -input=false -var=replicas=2 -detailed-exitcode >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The safe replica plan did not complete without changes: ✗ [DQ:capacity_plan]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
