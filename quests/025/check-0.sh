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
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app1, /srv/site/message contains north-ready : ✗ [DQ:content_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/message contains north-ready : ✗ [DQ:content_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/message contains north-ready : ✗ [DQ:content_3]'
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
printf '%s\n' 'On app1, /srv/site/message has mode 0644 : ✗ [DQ:mode_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/message has mode 0644 : ✗ [DQ:mode_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/message has mode 0644 : ✗ [DQ:mode_3]'
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
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app1, /srv/site/message contains north-ready : ✗ [DQ:content_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/message contains north-ready : ✗ [DQ:content_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/message contains north-ready : ✗ [DQ:content_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app1, /srv/site/message has mode 0644 : ✗ [DQ:mode_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/message has mode 0644 : ✗ [DQ:mode_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/message has mode 0644 : ✗ [DQ:mode_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
set +e
(
set -e
ansible-playbook rollout.yml >/tmp/idempotence-first.log
ansible-playbook rollout.yml >/tmp/idempotence-second.log
python3 -I - <<'DQ_RECAP'
import json
import re
from pathlib import Path


def count(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int) and value >= 0:
        return value
    if isinstance(value, str) and re.fullmatch(r'[0-9]+', value):
        return int(value)
    return None


def recap(text):
    # Read an actual recap, not task output which happens to mention a counter.
    records = []
    try:
        records.append(json.loads(text))
    except ValueError:
        for line in text.splitlines():
            try:
                records.append(json.loads(line))
            except ValueError:
                pass
    for record in reversed(records):
        if not isinstance(record, dict):
            continue
        stats = record.get('stats')
        if record.get('event') == 'playbook_on_stats':
            event = record.get('event_data', {})
            if isinstance(event, dict):
                stats = {host: {key: values.get(host) for key, values in event.items()
                                if isinstance(values, dict)}
                         for host in event.get('processed', {})}
        if isinstance(stats, dict):
            return {host: {({'failures':'failed','dark':'unreachable'}.get(key,key)): count(value)
                           for key, value in values.items()}
                    for host, values in stats.items() if isinstance(values, dict)}
    rows = {}
    body = text.rsplit('PLAY RECAP', 1)[-1]
    for line in body.splitlines():
        match = re.match(r'^([^\s:]+)\s*:\s*(.*)$', line)
        if not match:
            continue
        fields = re.findall(r'\b(ok|changed|unreachable|failed|skipped|rescued|ignored)\s*=\s*([0-9]+)(?=\s|$)', match[2])
        if fields:
            # Duplicate rows cannot stand in for another managed host.
            if match[1] in rows or len({key for key, _ in fields}) != len(fields):
                return {}
            rows[match[1]] = {key: int(value) for key, value in fields}
    return rows


def require_recaps(path, required, positive=(), prefix='recap'):
    try: text = Path(path).read_text()
    except OSError: text = ''
    rows = recap(text)
    failed = False
    for number in (1, 2, 3):
        row = rows.get('app' + str(number), {})
        ok = all(row.get(key) == value for key, value in required.items())
        ok = ok and all(isinstance(row.get(key), int) and row[key] > 0 for key in positive)
        if not ok:
            print('app' + str(number) + ' recap does not satisfy the required counters: ✗ [DQ:' + prefix + '_' + str(number) + ']')
            failed = True
    assert not failed, 'Every required managed host needs its own successful recap'

require_recaps('/tmp/idempotence-second.log', {'changed': 0, 'failed': 0})
DQ_RECAP

)
dq_action_rc=$?
set -e
if [ "$dq_action_rc" -ne 0 ]; then
if ! grep -Eq '^app1 .*changed=0 .*failed=0' /tmp/idempotence-second.log 2>/dev/null; then
printf '%s\n' 'Workstation /tmp/idempotence-second.log: app1 must report changed=0 and failed=0. ✗ [DQ:recap_1]'
fi
if ! grep -Eq '^app2 .*changed=0 .*failed=0' /tmp/idempotence-second.log 2>/dev/null; then
printf '%s\n' 'Workstation /tmp/idempotence-second.log: app2 must report changed=0 and failed=0. ✗ [DQ:recap_2]'
fi
if ! grep -Eq '^app3 .*changed=0 .*failed=0' /tmp/idempotence-second.log 2>/dev/null; then
printf '%s\n' 'Workstation /tmp/idempotence-second.log: app3 must report changed=0 and failed=0. ✗ [DQ:recap_3]'
fi
printf '%s\n' 'The workstation repeat-run check of rollout.yml or /tmp/idempotence-second.log failed : ✗ [DQ:repeat_run]'
exit 1
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
