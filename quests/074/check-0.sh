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
test -s check.log
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Workstation ~/quest/check.log is nonempty : ✗ [DQ:check_log]'
dq_group_failed=1
fi
(
set -e
test -s apply.log
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Workstation ~/quest/apply.log is nonempty : ✗ [DQ:apply_log]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY_CALLER'
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
dq_result_failed=0
set +e
(
set -e
dq_group_failed=0
set +e
(
set -e
python3 -I - <<'DQ_RECAP'
import json
import re
from pathlib import Path








from dq_check import ansible_recap as recap


from dq_check import require_recaps as _dq_recaps

def require_recaps(path, required, positive=(), prefix="recap"):
    return _dq_recaps(path, required, positive, prefix, dialect='shared_marker')

require_recaps('check.log', {'failed': 0}, positive=('changed','skipped'), prefix='preview_recaps')
DQ_RECAP

)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Workstation ~/quest/check.log reports predicted changes, skipped tasks and failed=0 for all three hosts : ✗ [DQ:preview_recaps]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || dq_result_failed=1
set -e
test "$dq_result_failed" -eq 0
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
DQ_LEGACY_CALLER
python3 -I - <<'DQ_CALLER_CAPABILITY'
import subprocess
import sys
try:
    result = subprocess.run(['/usr/bin/python3', '-I', '-c', "import sys\nfrom pathlib import Path\ntry:\n    facts = Path('/run/dq/facts/0')\n    for name in []:\n        if Path(name).read_bytes() != (facts / name).read_bytes():\n            print('Original caller input changed: ✗ [DQ:caller_original]')\n            sys.exit(1)\nexcept OSError:\n    print('Original caller input unavailable: ✗ [DQ:caller_original]')\n    sys.exit(1)\n\nimport hashlib,json,os,stat,subprocess,tempfile,time\nfrom pathlib import Path\nfrom dq_check import ansible_recap\n\nstarted=time.monotonic();deadline=started+14\n\ndef state(path):\n value=path.stat()\n return {'inode':value.st_ino,'mode':stat.S_IMODE(value.st_mode),'mtime_ns':value.st_mtime_ns,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}\n\nwith tempfile.TemporaryDirectory(prefix='dq-checkmode-check-') as folder:\n root=Path(folder);live=root/'message';cache=root/'cache';inspection=root/'service.pid';control=root/'unrelated-data'\n live.write_text('previous-probe\\n');cache.write_text('previous-probe\\n');inspection.write_text('1234\\n');control.write_text('preserve caller data\\n')\n paths=[live,cache,inspection,control]\n (root/'ansible.cfg').write_text('[defaults]\\ninterpreter_python=/usr/bin/python3\\n')\n (root/'inventory.json').write_text(json.dumps({'all':{'children':{'fleet':{'hosts':{'probe':{'ansible_connection':'local','ansible_python_interpreter':'/usr/bin/python3'}}}}}}))\n inputs={'delivery_path':str(live),'release_text':'next-probe','inspection_path':str(inspection),'service_reload':['/usr/bin/python3','/run/dq/facts/0/caller-cache.py',str(live),str(cache)],'ansible_connection':'local','ansible_python_interpreter':'/usr/bin/python3','ansible_become':False}\n env=dict(os.environ,ANSIBLE_CONFIG=str(root/'ansible.cfg'))\n def run(preview):\n  args=['ansible-playbook','-i',str(root/'inventory.json'),str(Path('rollout.yml').resolve()),'-e',json.dumps(inputs)]\n  if preview:args+=['--check','--diff']\n  result=subprocess.run(args,env=env,capture_output=True,text=True,timeout=max(.01,deadline-time.monotonic()))\n  \n  return result,ansible_recap(result.stdout).get('probe',{})\n before={str(p):state(p) for p in paths};result,row=run(True)\n valid=result.returncode==0 and row.get('changed',0)>0 and row.get('skipped',0)>0 and row.get('failed')==0 and all(state(p)==before[str(p)] for p in paths)\n reason='preview'\n if valid:\n  result,row=run(False);valid=result.returncode==0 and row.get('changed',0)>0 and row.get('failed')==0 and live.read_text().rstrip('\\n')=='next-probe' and cache.read_bytes()==live.read_bytes() and all(state(p)==before[str(p)] for p in [inspection,control]);reason='apply'\n if valid:\n  converged={str(p):state(p) for p in paths};result,row=run(True);valid=result.returncode==0 and row.get('changed')==0 and row.get('skipped',0)>0 and row.get('failed')==0 and all(state(p)==converged[str(p)] for p in paths);reason='converged-preview'\n \n if not valid:print('Preview or application contract failed: ✗ [DQ:preview_effects]')\n raise SystemExit(not valid)\n"], capture_output=True, text=True, timeout=14)
    if result.returncode:
        markers = ('[DQ:recovery_branches]', '[DQ:preview_effects]', '[DQ:caller_original]')
        for line in result.stdout.splitlines():
            if any(marker in line for marker in markers):
                print(line)
                break
        else:
            print('Caller replay could not be observed: ✗ [DQ:caller_observation]')
    sys.exit(result.returncode)
except subprocess.TimeoutExpired:
    print('Caller replay exceeded its budget: ✗ [DQ:caller_budget]')
    sys.exit(1)
DQ_CALLER_CAPABILITY
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-74'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 /srv/site/message: content = north-74 : ✗ [DQ:content_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-74'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 /srv/site/message: content = north-74 : ✗ [DQ:content_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-74'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 /srv/site/message: content = north-74 : ✗ [DQ:content_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 /srv/site/message: mode = 644 : ✗ [DQ:mode_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 /srv/site/message: mode = 644 : ✗ [DQ:mode_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 /srv/site/message: mode = 644 : ✗ [DQ:mode_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
test "$(curl -fsS --max-time 3 http://app1-${DQ_NAMESPACE#dq-}:8080)" = north-74
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 HTTP / on port 8080 = north-74 : ✗ [DQ:http_1]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app2-${DQ_NAMESPACE#dq-}:8080)" = north-74
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 HTTP / on port 8080 = north-74 : ✗ [DQ:http_2]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app3-${DQ_NAMESPACE#dq-}:8080)" = north-74
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 HTTP / on port 8080 = north-74 : ✗ [DQ:http_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
