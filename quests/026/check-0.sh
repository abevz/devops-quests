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
python3 -I - <<'DQ_MANAGED_CONTAINER'
import json
from pathlib import Path
import subprocess

def records(module):
    for item in module.get('resources', []):
        if item.get('mode') == 'managed' and item.get('type') == 'docker_container' and item.get('values', {}).get('name') in ('rail-worker','/rail-worker'):
            yield item
    for child in module.get('child_modules', []):
        yield from records(child)

try:
    state = json.loads(subprocess.check_output(['tofu','show','-json'], text=True, stderr=subprocess.DEVNULL, timeout=4))
    ok = bool(list(records(state.get('values', {}).get('root_module', {}))))
except Exception:
    ok = False
if not ok: print('The supplied route-processing container is not managed: ✗ [DQ:condition_0]')
raise SystemExit(int(not ok))
DQ_MANAGED_CONTAINER
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
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_MANAGED_CONTAINER_ID'
import json
from pathlib import Path
import subprocess

def records(module):
    for item in module.get('resources', []):
        if item.get('mode') == 'managed' and item.get('type') == 'docker_container' and item.get('values', {}).get('name') in ('rail-worker','/rail-worker'):
            yield item
    for child in module.get('child_modules', []):
        yield from records(child)

try:
    expected = Path('original-id').read_text().strip()
    observed = subprocess.check_output(['docker','inspect','rail-worker','--format','{{.Id}}'], text=True, stderr=subprocess.DEVNULL, timeout=4).strip()
    state = json.loads(subprocess.check_output(['tofu','show','-json'], text=True, stderr=subprocess.DEVNULL, timeout=4))
    live = bool(expected) and observed == expected
    tracked = bool(expected) and any(item.get('values', {}).get('id') == expected for item in records(state.get('values', {}).get('root_module', {})))
except Exception:
    live = tracked = False
if not live: print('The existing container ID differs from its receipt: ✗ [DQ:condition_1]')
if not tracked: print('The managed container ID differs from its receipt: ✗ [DQ:condition_2]')
raise SystemExit(int(not (live and tracked)))
DQ_MANAGED_CONTAINER_ID
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
failed=0
if ! docker inspect rail-worker 2>/dev/null | jq -e '.[0].State.Running' >/dev/null 2>&1; then
  printf '%s\n' 'rail-worker State.Running = true: ✗ [DQ:condition_3]'
  failed=1
fi
if ! docker inspect rail-worker 2>/dev/null | jq -e '.[0].State.Paused == false' >/dev/null 2>&1; then
  printf '%s\n' 'rail-worker State.Paused = false: ✗ [DQ:condition_4]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
