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
ansible-playbook --tags inspect rollout.yml > verification.log
test "$(grep -Ec '^app[123][[:space:]]+:.*changed=0.*unreachable=0.*failed=0' verification.log)" = 3
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/banner.txt)" = north-46'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/banner.txt)" = north-46'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/banner.txt)" = north-46'
)
[ $? -eq 0 ] || failed=1
exit "$failed"
