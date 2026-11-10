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

import subprocess

from dq_check import tofu_json

records = resource_records(tofu_json('show', '-json'))
south = file_resources(records, 'south.txt', in_module=True)
north = file_resources(records, 'north.txt', in_module=True)
distinct = any(s[0] != n[0] for s in south for n in north)
failed = False
if not south or not distinct:
    print('The south notice needs its own managed module instance: ✗ [DQ:condition_0]')
    failed = True
if not north or not distinct:
    print('The north notice needs its own managed module instance: ✗ [DQ:condition_1]')
    failed = True
sys.exit(int(failed))
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
failed=0
if ! test "$(cat south.txt 2>/dev/null)" = south-ready; then
  printf '%s\n' 'south.txt = south-ready: ✗ [DQ:condition_2]'
  failed=1
fi
if ! test "$(cat north.txt 2>/dev/null)" = north-ready; then
  printf '%s\n' 'north.txt = north-ready: ✗ [DQ:condition_3]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan -input=false -detailed-exitcode -no-color → 0: ✗ [DQ:condition_4]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
