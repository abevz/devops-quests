set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
test -s inspection.log
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
python3 - <<'TAGS'
import yaml
p=yaml.safe_load(open('rollout.yml'))
assert len(p)==1 and p[0]['hosts']=='fleet'
assert not p[0].get('tags'), 'Do not inherit inspection tags on the whole play'
tasks=p[0]['tasks']; assert len(tasks)==2
assert tasks[0]['tags']==['deploy'] and 'ansible.builtin.copy' in tasks[0]
assert tasks[1]['tags']==['inspect'] and tasks[1]['ansible.builtin.stat']=={'path':'/srv/site/banner.txt'}
assert not any(k in p[0] for k in ['pre_tasks','post_tasks','roles','handlers'])
TAGS
)
dq_action_rc=$?
set -e
if [ "$dq_action_rc" -ne 0 ]; then
printf '%s\n' 'Workstation rollout.yml must satisfy the retained safe-inspection scope check : ✗ [DQ:inspection_scope]'
exit 1
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
test -s inspection.log
python3 - <<'TAGS'
import yaml
p=yaml.safe_load(open('rollout.yml'))
assert len(p)==1 and p[0]['hosts']=='fleet'
assert not p[0].get('tags'), 'Do not inherit inspection tags on the whole play'
tasks=p[0]['tasks']; assert len(tasks)==2
assert tasks[0]['tags']==['deploy'] and 'ansible.builtin.copy' in tasks[0]
assert tasks[1]['tags']==['inspect'] and tasks[1]['ansible.builtin.stat']=={'path':'/srv/site/banner.txt'}
assert not any(k in p[0] for k in ['pre_tasks','post_tasks','roles','handlers'])
TAGS
set +e
(
set -e
ansible-playbook --tags inspect rollout.yml > verification.log
test "$(grep -Ec '^app[123][[:space:]]+:.*changed=0.*unreachable=0.*failed=0' verification.log)" = 3
)
dq_action_rc=$?
set -e
if [ "$dq_action_rc" -ne 0 ]; then
if ! grep -Eq '^app1[[:space:]]+:.*changed=0.*unreachable=0.*failed=0' verification.log 2>/dev/null; then
printf '%s\n' 'Workstation verification.log: app1 must report changed=0, unreachable=0 and failed=0. ✗ [DQ:inspection_recap_1]'
fi
if ! grep -Eq '^app2[[:space:]]+:.*changed=0.*unreachable=0.*failed=0' verification.log 2>/dev/null; then
printf '%s\n' 'Workstation verification.log: app2 must report changed=0, unreachable=0 and failed=0. ✗ [DQ:inspection_recap_2]'
fi
if ! grep -Eq '^app3[[:space:]]+:.*changed=0.*unreachable=0.*failed=0' verification.log 2>/dev/null; then
printf '%s\n' 'Workstation verification.log: app3 must report changed=0, unreachable=0 and failed=0. ✗ [DQ:inspection_recap_3]'
fi
printf '%s\n' 'Workstation verification.log must report changed=0, unreachable=0 and failed=0 for app1, app2 and app3 : ✗ [DQ:inspection_run]'
exit 1
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/banner.txt)" = north-46'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app1, /srv/site/banner.txt contains north-46 : ✗ [DQ:banner_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/banner.txt)" = north-46'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/banner.txt contains north-46 : ✗ [DQ:banner_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/banner.txt)" = north-46'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/banner.txt contains north-46 : ✗ [DQ:banner_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
