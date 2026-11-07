set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
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

matched = file_resources(resource_records(tofu_json("show", "-json")), 'notice.txt', in_module=False)
if not matched:
    print("Managed producer file is missing: ✗ [DQ:condition_0]")
    sys.exit(1)
DQ_PROPERTY
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan -input=false -detailed-exitcode -no-color → 0: ✗ [DQ:condition_1]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
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

import re
records = file_resources(resource_records(tofu_json('show', '-json')), 'notice.txt')
addresses = [r.get('address') for _, r in records]
if not addresses or not all(isinstance(a, str) and a for a in addresses):
    print('Managed notice removal cannot be verified: ✗ [DQ:condition_2]')
    sys.exit(1)
# A different protected resource must not hide an unprotected notice.
failed = False
logs = []
for address in addresses:
    result = subprocess.run(['tofu', 'plan', '-destroy', '-input=false', '-no-color', '-target=' + address], capture_output=True, text=True)
    log = result.stdout + result.stderr
    logs.append(log)
    if result.returncode == 0:
        print('Planning removal of the managed notice was not refused: ✗ [DQ:condition_2]')
        failed = True
    plain = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', log)
    plain = ' '.join(plain.replace('│', ' ').split())
    expected = r'\bResource (?:instance )?' + re.escape(address) + r' has (?:lifecycle\.)?prevent_destroy\b'
    if not re.search(expected, plain):
        print('The notice refusal was not its own resource protection: ✗ [DQ:condition_3]')
        failed = True
Path('destroy-plan.log').write_text('\n'.join(logs))
sys.exit(int(failed))
DQ_PROPERTY
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! test "$(cat notice.txt 2>/dev/null)" = north-ready; then
  printf '%s\n' 'notice.txt = north-ready: ✗ [DQ:condition_4]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
