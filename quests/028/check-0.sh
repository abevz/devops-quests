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
: > rollout-events.jsonl
ansible-playbook rollout.yml >/tmp/serial-check.log
python3 - <<'CHECK'
import json
e=[json.loads(x) for x in open('rollout-events.jsonl')]
h=[x['host'] for x in e if 'host' in x and x['task']=='Deliver the route message']
assert h[-3:]==['app1','app2','app3']
# Every batch starts the task again; one task start for all three hosts is not serial=1.
starts=[x for x in e if 'host' not in x and x['task']=='Deliver the route message']
assert len(starts)>=3
CHECK
)
dq_action_rc=$?
set -e
if [ "$dq_action_rc" -ne 0 ]; then
printf '%s\n' 'Workstation rollout-events.jsonl must show app1, app2, app3 delivery in one-host batches : ✗ [DQ:delivery_trace]'
exit 1
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
