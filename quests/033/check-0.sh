set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
failed=0
if ! test "$(cat east.txt 2>/dev/null)" = open; then
  printf '%s\n' 'east.txt = open: ✗ [DQ:condition_0]'
  failed=1
fi
if ! test "$(cat north.txt 2>/dev/null)" = open; then
  printf '%s\n' 'north.txt = open: ✗ [DQ:condition_8]'
  failed=1
fi
if ! test "$(cat south.txt 2>/dev/null)" = held; then
  printf '%s\n' 'south.txt = held: ✗ [DQ:condition_9]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! tofu output -json routes > current-ids.json 2>/dev/null; then
  printf '%s\n' 'tofu output -json routes: ✗ [DQ:condition_1]'
  failed=1
fi
if ! jq -e --slurpfile old original-ids.json '.north==$old[0].north' current-ids.json >/dev/null 2>&1; then
  printf '%s\n' 'routes.north = original-ids.json north: ✗ [DQ:condition_2]'
  failed=1
fi
if ! jq -e --slurpfile old original-ids.json '.south==$old[0].south' current-ids.json >/dev/null 2>&1; then
  printf '%s\n' 'routes.south = original-ids.json south: ✗ [DQ:condition_3]'
  failed=1
fi
if ! jq -e '(.east|type)=="string"' current-ids.json >/dev/null 2>&1; then
  printf '%s\n' 'routes.east type = string: ✗ [DQ:condition_4]'
  failed=1
fi
if ! jq -e 'length==3' current-ids.json >/dev/null 2>&1; then
  printf '%s\n' 'routes length = 3: ✗ [DQ:condition_5]'
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


def read_json(path, successful=True):
    if not successful:
        return None
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None


def resource_records(document, section='values'):
    if not isinstance(document, dict):
        return []
    values = document.get(section)
    root = values.get('root_module') if isinstance(values, dict) else None
    if not isinstance(root, dict):
        return []
    records = []
    pending = [root]
    while pending:
        module = pending.pop()
        resources = module.get('resources') or []
        children = module.get('child_modules') or []
        if not isinstance(resources, list) or not isinstance(children, list):
            return []
        for resource in resources:
            if not isinstance(resource, dict):
                return []
            records.append((module.get('address'), resource))
        if not all(isinstance(child, dict) for child in children):
            return []
        pending.extend(children)
    return records


def same_target(value, expected, existing=False):
    if not isinstance(value, str) or not value:
        return False
    try:
        expanded = os.path.expanduser(value)
        parent, leaf = os.path.split(expanded)
        if leaf in ('', '.', '..'):
            return False
        # Validate raw traversal before pathlib normalizes it: file/.. and
        # absent/../file are not usable aliases of an existing file.
        if not stat.S_ISDIR(os.stat(parent or '.').st_mode):
            return False
        target = Path(expected)
        if existing or target.exists():
            if not stat.S_ISREG(os.stat(expanded).st_mode):
                return False
            return Path(expanded).resolve(strict=True) == target.resolve(strict=True)
        candidate = Path(parent or '.').resolve(strict=True) / leaf
        return candidate == target.parent.resolve(strict=True) / target.name
    except (OSError, RuntimeError, ValueError):
        return False


def file_resources(records, filename, in_module=False):
    found = []
    for module, resource in records:
        values = resource.get('values')
        if (resource.get('mode') == 'managed' and resource.get('type') == 'local_file'
                and isinstance(values, dict) and same_target(values.get('filename'), filename)
                and (not in_module or isinstance(module, str) and bool(module))):
            found.append((module, resource))
    return found


def number_is(value, expected):
    return type(value) in (int, float) and value == expected

import subprocess

def tofu_json(*arguments):
    result = subprocess.run(['tofu', *arguments], capture_output=True, text=True)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except ValueError:
        return None

records = resource_records(tofu_json('show', '-json'))
if not all(file_resources(records, name) for name in ('north.txt', 'south.txt', 'east.txt')):
    print('The added route is not in the managed route set: ✗ [DQ:condition_6]')
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
failed=0
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan -input=false -detailed-exitcode -no-color → 0: ✗ [DQ:condition_7]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
