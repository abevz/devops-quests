set -euo pipefail
cd ~/quest
sha256sum -c previous.sha256 >/dev/null
python3 - <<'SCOPE'
import yaml
p=yaml.safe_load(open('rollout.yml'))[0]
assert p['hosts']=='fleet' and p.get('serial')==1
b=p['tasks'][0];assert b.get('rescue') and b.get('always')
assert b['rescue'][0]['ansible.builtin.copy']=={'src':'previous.txt','dest':'/srv/site/message','mode':'0644'}
assert b['rescue'][0]['notify']=='Reload banner'
SCOPE
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/message)" = stable-63; test "$(cat /srv/site/recovery-checked)" = checked; test "$(stat -c %a /srv/site/message)" = 644'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/message)" = stable-63; test "$(cat /srv/site/recovery-checked)" = checked; test "$(stat -c %a /srv/site/message)" = 644'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/message)" = stable-63; test "$(cat /srv/site/recovery-checked)" = checked; test "$(stat -c %a /srv/site/message)" = 644'
for i in 1 2 3; do test "$(curl -fsS --max-time 3 http://app$i-${DQ_NAMESPACE#dq-}:8080)" = stable-63; done
