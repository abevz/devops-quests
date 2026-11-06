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
python3 - <<'SCOPE'
import sys
import yaml
try:
    play = yaml.safe_load(open('rollout.yml'))[0]
    task = play['tasks'][0]
    rescue = task.get('rescue') or []
    first = rescue[0] if rescue else {}
    if not all(isinstance(value, dict) for value in (play, task, first)):
        raise TypeError('play, task and rescue action must be mappings')
except (OSError, ValueError, TypeError, KeyError, IndexError, AttributeError, yaml.YAMLError):
    play, task, first = {}, {}, {}
checks = [
    ('first play hosts = fleet [DQ:hosts]', play.get('hosts') == 'fleet'),
    ('first play serial = 1 [DQ:serial]', type(play.get('serial')) is int and play.get('serial') == 1),
    ('first task block is a nonempty list [DQ:block]', isinstance(task.get('block'), list) and bool(task.get('block'))),
    ('first task rescue is a nonempty list [DQ:rescue]', isinstance(task.get('rescue'), list) and bool(task.get('rescue'))),
    ('first task always is a nonempty list [DQ:always]', isinstance(task.get('always'), list) and bool(task.get('always'))),
    ('first rescue copy = previous.txt to /srv/site/message mode 0644 [DQ:copy]', first.get('ansible.builtin.copy') == {'src': 'previous.txt', 'dest': '/srv/site/message', 'mode': '0644'}),
    ('first rescue notify = Reload banner [DQ:notify]', first.get('notify') == 'Reload banner'),
]
for label, ok in checks:
    if not ok: print(label + ': ✗')
sys.exit(not all(ok for _, ok in checks))
SCOPE
)
[ $? -eq 0 ] || failed=1
(
set -e
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
[ $? -eq 0 ] || failed=1
exit "$failed"
