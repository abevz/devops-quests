set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
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
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat release.txt)" = release-30
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
