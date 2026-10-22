set -euo pipefail
cd ~/quest
python3 - <<'CHECK_MODE_TASK'
import yaml
p=yaml.safe_load(open('rollout.yml'))[0];assert p['hosts']=='fleet'
t=p['tasks'];assert len(t)==2
assert t[1]['ansible.builtin.command']=='cat /run/quest-service.pid'
assert t[1]['changed_when'] is False and 'check_mode' not in t[1]
assert t[0]['ansible.builtin.copy']=={'dest':'/srv/site/message','content':'north-74\n','mode':'0644'}
assert t[0]['notify']=='Reload banner'
CHECK_MODE_TASK
test -s check.log
test -s apply.log
test "$(grep -Ec '^app[123][[:space:]]+:.*changed=[1-9].*failed=0.*skipped=[1-9]' check.log)" = 3
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/message)" = north-74; test "$(stat -c %a /srv/site/message)" = 644'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/message)" = north-74; test "$(stat -c %a /srv/site/message)" = 644'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/message)" = north-74; test "$(stat -c %a /srv/site/message)" = 644'
for i in 1 2 3; do test "$(curl -fsS --max-time 3 http://app$i-${DQ_NAMESPACE#dq-}:8080)" = north-74; done
