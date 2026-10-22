set -euo pipefail
cd ~/quest
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/role.txt)" = north:shared'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/role.txt)" = north:shared'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/role.txt)" = north:shared'
python3 - <<'PY'
import yaml
assert yaml.safe_load(open('roles/station/defaults/main.yml'))=={'route':'retired','platform':'shared'}
PY
