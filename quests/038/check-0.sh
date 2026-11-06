set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/role.txt)" = north:shared'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/role.txt)" = north:shared'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/role.txt)" = north:shared'
)
[ $? -eq 0 ] || failed=1
(
set -e
python3 - <<'PY'
import yaml
assert yaml.safe_load(open('roles/station/defaults/main.yml'))=={'route':'retired','platform':'shared'}
PY
)
[ $? -eq 0 ] || failed=1
exit "$failed"
