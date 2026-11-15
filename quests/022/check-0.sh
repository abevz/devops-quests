set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'grep -qx station=app1 /srv/site/message'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app1, /srv/site/message contains the complete line station=app1 : ✗ [DQ:identity_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'grep -qx station=app2 /srv/site/message'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/message contains the complete line station=app2 : ✗ [DQ:identity_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'grep -qx station=app3 /srv/site/message'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/message contains the complete line station=app3 : ✗ [DQ:identity_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
cd ~/quest
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY_ANSIBLE_022_1'
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'grep -qx route=north /srv/site/message'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app1, /srv/site/message contains the complete line route=north : ✗ [DQ:route_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'grep -qx route=north /srv/site/message'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/message contains the complete line route=north : ✗ [DQ:route_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'grep -qx route=north /srv/site/message'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/message contains the complete line route=north : ✗ [DQ:route_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
DQ_LEGACY_ANSIBLE_022_1
python3 -I - <<'DQ_TEMPLATE_CAPABILITY'
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from dq_check import ansible_recap

failed = False
deadline = time.monotonic() + 10


def require(value, marker):
    global failed
    if not value:
        print('Input contract is unmet: ✗ [DQ:' + marker + ']')
        failed = True


def command(args, env=None):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError('Observation budget exhausted')
    return subprocess.run(args, env=env, capture_output=True, text=True, timeout=remaining)


def supplied(name):
    return json.loads((Path('/run/dq/facts/0') / name).read_text())


def local_inventory(names):
    return {'all': {'hosts': {name: {'ansible_connection': 'local', 'ansible_python_interpreter': '/usr/bin/python3'} for name in names}}}


def subset(actual, expected):
    return isinstance(actual, dict) and all(actual.get(key) == value for key, value in expected.items())
try:
    contract = supplied('template-contract.json')
    cases = contract['cases']
    with tempfile.TemporaryDirectory(prefix='dq-template-check-') as folder:
        root = Path(folder)
        (root / 'ansible.cfg').write_text('[defaults]\ninterpreter_python=/usr/bin/python3\n')
        (root / 'inventory.json').write_text(json.dumps(local_inventory(cases)))
        play = [{'hosts': 'all', 'gather_facts': False, 'become': False, 'tasks': [
            {'name': 'Render the caller inputs', 'ansible.builtin.template': {
                'src': str(Path(contract['template']).resolve()),
                'dest': str(root) + '/{{ inventory_hostname }}', 'mode': '0600'}}]}]
        (root / 'play.json').write_text(json.dumps(play))
        inputs = {'station_routes': {name: {'active': route} for name, route in cases.items()}}
        result = command(['/opt/ansible/bin/ansible-playbook', '-i', str(root / 'inventory.json'), str(root / 'play.json'), '-e', json.dumps(inputs)], dict(os.environ, ANSIBLE_CONFIG=str(root / 'ansible.cfg')))
        require(result.returncode == 0, 'template_render')
        if result.returncode == 0:
            for name, route in cases.items():
                lines = (root / name).read_text().splitlines()
                for key, value in [('station', name), ('route', route)]:
                    actual = [line.partition('=')[2] for line in lines if line.startswith(key + '=')]
                    require(bool(actual) and all(item == value for item in actual), 'template_inputs')
except (KeyError, TypeError, ValueError, OSError, subprocess.SubprocessError):
    require(False, 'template_observation')
sys.exit(int(failed))
DQ_TEMPLATE_CAPABILITY
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
exit "$failed"
