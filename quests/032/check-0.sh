set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
test "$(cat fleet.txt)" = "$(printf 'app1
app2
app3')"
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(stat -c %a fleet.txt)" = 644
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test ! -e /srv/site/fleet.txt'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'No /srv/site/fleet.txt is present on app1 : ✗ [DQ:absent_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test ! -e /srv/site/fleet.txt'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'No /srv/site/fleet.txt is present on app2 : ✗ [DQ:absent_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test ! -e /srv/site/fleet.txt'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'No /srv/site/fleet.txt is present on app3 : ✗ [DQ:absent_3]'
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
python3 -I - <<'DQ_DELEGATION'
import copy
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time

report = Path('fleet.txt')
original = None
deadline = time.monotonic() + 18

def run(command):
    remaining = deadline - time.monotonic()
    if remaining <= 0: raise TimeoutError()
    result = subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=remaining)
    if result.returncode: raise RuntimeError('Report run did not complete')
    return result.stdout

def members(data, group, seen=None):
    seen = set() if seen is None else seen
    if group in seen: return set()
    seen.add(group)
    entry = data.get(group, {})
    found = set(entry.get('hosts', []))
    for child in entry.get('children', []): found |= members(data, child, seen)
    return found

try:
    metadata = report.stat()
    original = (report.read_bytes(), stat.S_IMODE(metadata.st_mode), metadata.st_atime_ns, metadata.st_mtime_ns, os.readlink(report) if report.is_symlink() else None)
    source = json.loads(run(['ansible-inventory','--list']))
    hosts = sorted(members(source,'fleet'))
    if len(hosts) < 2: raise RuntimeError('Insufficient supplied fleet')
    hostvars = source.get('_meta', {}).get('hostvars', {})
    inventory = {group:{'hosts':{host:hostvars.get(host,{}) for host in entry.get('hosts',[])},'children':{child:{} for child in entry.get('children',[])},'vars':entry.get('vars',{})}
                 for group,entry in source.items() if group != '_meta'}
    alias = 'dq_report_probe'
    while alias in members(source,'all'): alias += '_new'
    added = copy.deepcopy(inventory)
    alias_variables = copy.deepcopy(hostvars.get(hosts[0],{}))
    alias_variables.setdefault('ansible_host',hosts[0])
    added.setdefault('fleet',{}).setdefault('hosts',{})[alias] = alias_variables
    removed = copy.deepcopy(inventory)
    for entry in removed.values(): entry.get('hosts',{}).pop(hosts[1],None)
    for variant, expected in ((added,sorted(hosts+[alias])),(removed,sorted(set(hosts)-{hosts[1]}))):
        with tempfile.NamedTemporaryFile(mode='w+',suffix='.json') as temporary:
            json.dump(variant,temporary);temporary.flush()
            run(['ansible-playbook','-i',temporary.name,'rollout.yml'])
        if report.read_text().splitlines() != expected:
            raise RuntimeError('Report is not derived from current sorted membership')
except Exception:
    print('The report must follow sorted current fleet membership: ✗ [DQ:probe_0_3]')
    raise SystemExit(1)
finally:
    if original is not None:
        data,mode,atime,mtime,link = original
        # Restore only this probe's output; preserve the learner's working report.
        if report.is_symlink() and (link is None or os.readlink(report) != link): report.unlink()
        if link is not None and not report.is_symlink():
            report.unlink(missing_ok=True);report.symlink_to(link)
        report.write_bytes(data)
        report.chmod(mode)
        os.utime(report,ns=(atime,mtime))

DQ_DELEGATION
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
exit "$failed"
