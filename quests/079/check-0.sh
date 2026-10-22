set -euo pipefail
cd ~/quest
python3 - <<'DECLARATION'
import yaml
p=yaml.safe_load(open('rollout.yml'))[0]
assert p['hosts']=='fleet' and not any(k in p for k in ['pre_tasks','post_tasks','roles','check_mode','changed_when'])
t=p['tasks'];assert len(t)==3
assert t[0]['ansible.builtin.file']=={'path':'/srv/site/config','state':'directory','mode':'0755'}
assert t[1]['ansible.builtin.copy']=={'dest':'/srv/site/message','content':'north-79\n','mode':'0644'}
assert t[1]['notify']=='Reload banner'
assert t[2]['ansible.builtin.copy']=={'dest':'/srv/site/config/route','content':'route=north\n','mode':'0644'}
assert all(not any(k in x for k in ['changed_when','check_mode','when']) for x in t)
DECLARATION
test -s repair.log
test "$(grep -Ec '^app[123][[:space:]]+:.*changed=0.*unreachable=0.*failed=0' second.log)" = 3
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(stat -c %a /srv/site/config)" = 755; test "$(stat -c %a /srv/site/message)" = 644; test "$(cat /srv/site/message)" = north-79; test "$(cat /srv/site/config/route)" = route=north'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(stat -c %a /srv/site/config)" = 755; test "$(stat -c %a /srv/site/message)" = 644; test "$(cat /srv/site/message)" = north-79; test "$(cat /srv/site/config/route)" = route=north'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(stat -c %a /srv/site/config)" = 755; test "$(stat -c %a /srv/site/message)" = 644; test "$(cat /srv/site/message)" = north-79; test "$(cat /srv/site/config/route)" = route=north'
for i in 1 2 3; do test "$(curl -fsS --max-time 3 http://app$i-${DQ_NAMESPACE#dq-}:8080)" = north-79; done
