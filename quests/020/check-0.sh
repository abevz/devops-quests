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
set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

def require(good, marker):
    if not good:raise AssertionError(marker)

try:
    document=json.loads(subprocess.check_output(['tofu','show','-json'],stderr=subprocess.DEVNULL,timeout=5))
    pending=[document['values']['root_module']];found=False
    while pending:
        module=pending.pop();pending.extend(module.get('child_modules',[]))
        for resource in module.get('resources',[]):
            value=resource.get('values',{});filename=value.get('filename')
            if resource.get('mode')=='managed' and resource.get('type')=='local_file' and isinstance(filename,str):
                try:found=found or Path(filename).samefile('release.txt')
                except OSError:pass
    require(found,'state')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'state'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
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
set -euo pipefail
cd ~/quest
failed=0
if ! test "$(cat release.txt 2>/dev/null)" = release-20; then printf '%s\n' 'release.txt = release-20: ✗ [DQ:file]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! test "$(tofu output -raw release 2>/dev/null)" = release-20; then printf '%s\n' 'tofu output release = release-20: ✗ [DQ:output]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then printf '%s\n' 'tofu plan exits 0: ✗ [DQ:plan]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
