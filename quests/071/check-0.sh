set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
failed=0
if ! test "$(tofu output -raw north_id 2>/dev/null)" = "$(cat /run/dq/facts/0/original-north-id 2>/dev/null)" || ! test -s /run/dq/facts/0/original-north-id; then
  printf '%s\n' 'north_id = /run/dq/facts/0/original-north-id: ✗ [DQ:condition_0]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! test "$(cat north.txt 2>/dev/null)" = north-71; then
  printf '%s\n' 'north.txt = north-71: ✗ [DQ:condition_1]'
  failed=1
fi
if ! test "$(cat south.txt 2>/dev/null)" = south-71; then
  printf '%s\n' 'south.txt = south-71: ✗ [DQ:condition_2]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
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

import subprocess

from dq_check import tofu_json

records = resource_records(tofu_json('show', '-json'))
if len(records) != 2 or not all(len(file_resources(records, name)) == 1 for name in ('north.txt', 'south.txt')):
    print('State must track exactly both configured route files: ✗ [DQ:condition_3]')
    sys.exit(1)
DQ_PROPERTY
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

plan = read_json('recovery-plan.json')
changes = plan.get('resource_changes') if isinstance(plan, dict) else None
failed = False
if not isinstance(changes, list) or len(changes) != 2:
    print('Saved recovery plan must contain two resource entries: ✗ [DQ:condition_4]')
    failed = True
try:
    original = Path('/run/dq/facts/0/original-north-id').read_text().strip()
except OSError:
    original = ''
north = south = False
for resource in changes if isinstance(changes, list) else []:
    if resource.get('mode') != 'managed' or resource.get('type') != 'local_file':
        continue
    change = resource.get('change', {})
    before, after = change.get('before') or {}, change.get('after') or {}
    if change.get('actions') == ['no-op'] and same_target(before.get('filename'), 'north.txt') and before.get('id') == original and original:
        north = True
    if change.get('actions') == ['create'] and same_target(after.get('filename'), 'south.txt'):
        south = True
if not north:
    print('Saved plan must leave the original file unchanged: ✗ [DQ:condition_5]')
    failed = True
if not south:
    print('Saved plan must create the missing file: ✗ [DQ:condition_6]')
    failed = True
sys.exit(int(failed))
DQ_PROPERTY
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
failed=0
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan -input=false -detailed-exitcode -no-color → 0: ✗ [DQ:condition_7]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
