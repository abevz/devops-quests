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
python3 -I - <<'DQ_PROPERTY'
import json
import os
import stat
import sys
from pathlib import Path


from dq_check import read_json


from dq_check import resource_records


from dq_check import same_target


from dq_check import file_resources


from dq_check import number_is

plan = read_json('rejected-plan.json')
try:
    original = Path('original-id').read_text().strip()
except OSError:
    original = ''
changes = plan.get('resource_changes', []) if isinstance(plan, dict) else []
valid = False
for resource in changes if isinstance(changes, list) else []:
    change = resource.get('change', {})
    before = change.get('before') or {}
    actions = change.get('actions')
    if (resource.get('mode') == 'managed' and resource.get('type') == 'local_file'
            and same_target(before.get('filename'), 'ledger.txt')
            and original and before.get('id') == original
            and isinstance(actions, list) and sorted(actions) == ['create', 'delete']):
        valid = True
sys.exit(0 if valid else 1)
DQ_PROPERTY
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
test "$(cat ledger.txt)" = revision-36
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The ledger content could not be verified: ✗ [DQ:ledger_content]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
test ! -e retired-ledger.txt
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The rejected ledger path is still present: ✗ [DQ:retired_absent]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
test "$(tofu output -raw ledger_id)" = "$(cat original-id)"
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The ledger output could not be matched to the original ID: ✗ [DQ:ledger_identity]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The recovery plan did not finish without changes: ✗ [DQ:ledger_plan]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
