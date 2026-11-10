set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu validate -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
sha256sum -c /run/dq/facts/0/original-module.sha256 >/dev/null
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
north = file_resources(records, 'north.txt', in_module=True)
south = file_resources(records, 'south.txt', in_module=True)
valid = len(records) == 2 and len(north) == len(south) == 1 and north[0][0] != south[0][0]
sys.exit(0 if valid else 1)
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
test "$(cat north.txt)" = dispatch:north
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat south.txt)" = dispatch:north:south
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu output -json routes | jq -e '.=={north:"dispatch:north",south:"dispatch:north:south"}' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
