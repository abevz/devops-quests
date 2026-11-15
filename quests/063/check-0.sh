set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
if ! sha256sum -c previous.sha256 >/dev/null 2>&1; then printf '%s\n' 'previous.txt matches previous.sha256: ✗ [DQ:checksum]'; exit 1; fi
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
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY_CALLER'
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = stable-63'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 /srv/site/message: content = stable-63 : ✗ [DQ:content_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = stable-63'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 /srv/site/message: content = stable-63 : ✗ [DQ:content_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = stable-63'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 /srv/site/message: content = stable-63 : ✗ [DQ:content_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
DQ_LEGACY_CALLER
python3 -I - <<'DQ_CALLER_CAPABILITY'
import subprocess
import sys
try:
    result = subprocess.run(['/usr/bin/python3', '-I', '-c', "import sys\nfrom pathlib import Path\ntry:\n    facts = Path('/run/dq/facts/0')\n    for name in ['previous.txt', 'previous.sha256']:\n        if Path(name).read_bytes() != (facts / name).read_bytes():\n            print('Original caller input changed: ✗ [DQ:caller_original]')\n            sys.exit(1)\nexcept OSError:\n    print('Original caller input unavailable: ✗ [DQ:caller_original]')\n    sys.exit(1)\n\nimport hashlib,json,os,stat,subprocess,tempfile,time\nfrom pathlib import Path\nfrom dq_check import ansible_recap\nstart=time.monotonic();deadline=start+14\nwith tempfile.TemporaryDirectory(prefix='dq-recovery-check-') as folder:\n root=Path(folder);(root/'ansible.cfg').write_text('[defaults]\\ninterpreter_python=/usr/bin/python3\\n');(root/'inventory.json').write_text(json.dumps({'all':{'children':{'fleet':{'hosts':{'probe':{'ansible_connection':'local','ansible_python_interpreter':'/usr/bin/python3'}}}}}}))\n results=[];valid=True\n for name,candidate,previous,corrupt in [('accepted','approved','fallback-one',False),('rejected','unapproved-candidate','fallback-two',False),('untrusted','unapproved-candidate','fallback-three',True)]:\n  work=root/name;work.mkdir();live=work/'message';cache=work/'cache';backup=work/'previous';incoming=work/'candidate';control=work/'unrelated';marker=work/'checked'\n  live.write_text('retain-current\\n');cache.write_text('retain-current\\n');backup.write_text(previous+'\\n');incoming.write_text(candidate+'\\n');control.write_text('preserve caller data\\n');expected=hashlib.sha256(backup.read_bytes()).hexdigest()\n  if corrupt:backup.write_text('tampered-backup\\n')\n  def snapshot(p):\n   s=p.stat();return (s.st_ino,s.st_mtime_ns,stat.S_IMODE(s.st_mode),p.read_bytes())\n  before={p:snapshot(p) for p in [live,cache,backup,incoming,control]}\n  inputs={'delivery_path':str(live),'candidate_path':str(incoming),'previous_path':str(backup),'previous_sha256':expected,'recovery_marker':str(marker),'service_reload':['/usr/bin/python3','/run/dq/facts/0/caller-cache.py',str(live),str(cache)],'ansible_connection':'local','ansible_python_interpreter':'/usr/bin/python3','ansible_become':False}\n  result=subprocess.run(['ansible-playbook','-i',str(root/'inventory.json'),str(Path('rollout.yml').resolve()),'-e',json.dumps(inputs)],env=dict(os.environ,ANSIBLE_CONFIG=str(root/'ansible.cfg')),capture_output=True,text=True,timeout=max(.01,deadline-time.monotonic()))\n  row=ansible_recap(result.stdout).get('probe',{})\n  if corrupt:passed=result.returncode!=0 and all(snapshot(p)==before[p] for p in before)\n  else:\n   wanted=candidate if candidate=='approved' else previous\n   passed=result.returncode==0 and live.read_text().rstrip('\\n')==wanted and cache.read_bytes()==live.read_bytes() and marker.read_text().strip()=='checked' and all(snapshot(p)==before[p] for p in [backup,incoming,control]) and row.get('failed')==0 and (row.get('rescued',0)>0 if candidate!='approved' else row.get('rescued',0)==0)\n  results.append({'case':name,'exit':result.returncode,'recap':row,'passed':passed});valid=valid and passed\n  if not passed:break\n \n if not valid:print('Recovery caller contract failed: ✗ [DQ:recovery_branches]')\n raise SystemExit(not valid)\n"], capture_output=True, text=True, timeout=14)
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
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 /srv/site/message: mode = 644 : ✗ [DQ:mode_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 /srv/site/message: mode = 644 : ✗ [DQ:mode_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
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
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/recovery-checked)" = checked'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 /srv/site/recovery-checked: content = checked : ✗ [DQ:marker_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/recovery-checked)" = checked'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 /srv/site/recovery-checked: content = checked : ✗ [DQ:marker_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/recovery-checked)" = checked'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 /srv/site/recovery-checked: content = checked : ✗ [DQ:marker_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_result_failed=0
set +e
(
set -e
dq_group_failed=0
set +e
(
set -e
test "$(curl -fsS --max-time 3 http://app1-${DQ_NAMESPACE#dq-}:8080)" = stable-63
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 HTTP / on port 8080 = stable-63 : ✗ [DQ:http_1]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app2-${DQ_NAMESPACE#dq-}:8080)" = stable-63
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 HTTP / on port 8080 = stable-63 : ✗ [DQ:http_2]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app3-${DQ_NAMESPACE#dq-}:8080)" = stable-63
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 HTTP / on port 8080 = stable-63 : ✗ [DQ:http_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || dq_result_failed=1
set -e
test "$dq_result_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
