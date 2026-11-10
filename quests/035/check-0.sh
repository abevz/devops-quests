set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
test "$(cat safety-check.txt)" = 'healthy fleet checked'
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
python3 -I - <<'DQ_UNREACHABLE'
import json,re
from pathlib import Path
text=Path('probe.log').read_text()
found=bool(re.search(r'(?m)^[^\n]*\bUNREACHABLE!\s*=>',text))
try: records=[json.loads(text)]
except ValueError:
 records=[]
 for line in text.splitlines():
  try: records.append(json.loads(line))
  except ValueError: pass
for record in records:
 if not isinstance(record,dict):continue
 found=found or record.get('event')=='runner_on_unreachable'
 for play in record.get('plays',[]):
  for task in play.get('tasks',[]):
   found=found or any(isinstance(v,dict) and v.get('unreachable') is True for v in task.get('hosts',{}).values())
assert found, 'The probe log needs an actual unreachable result'
DQ_UNREACHABLE
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_1]'
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
python3 -I - <<'DQ_RECAP'
import json
import re
from pathlib import Path








from dq_check import ansible_recap as recap


from dq_check import require_recaps as _dq_recaps

def require_recaps(path, required, positive=(), prefix="recap"):
    return _dq_recaps(path, required, positive, prefix, dialect='by_host')

require_recaps('probe.log', {'unreachable': 0, 'failed': 0})
DQ_RECAP
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
exit "$failed"
