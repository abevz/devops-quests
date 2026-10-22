set -euo pipefail
cd ~/quest
python3 - <<'SECRET'
import yaml
p=yaml.safe_load(open('rollout.yml'))[0];assert p['hosts']=='fleet'
t=p['tasks'][0];assert t['no_log'] is True
assert t['ansible.builtin.copy']['mode']=='0600'
assert t['ansible.builtin.copy']['dest']=='/srv/site/station-token'
SECRET
test -s deployment.log
if grep -Fq 'game-station-secret-69' deployment.log; then exit 1; fi
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(stat -c %a /srv/site/station-token)" = 600; test "$(cat /srv/site/station-token)" = game-station-secret-69'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(stat -c %a /srv/site/station-token)" = 600; test "$(cat /srv/site/station-token)" = game-station-secret-69'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(stat -c %a /srv/site/station-token)" = 600; test "$(cat /srv/site/station-token)" = game-station-secret-69'
