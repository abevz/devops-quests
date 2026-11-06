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
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/role.txt)" = north:shared'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app1, /srv/site/role.txt contains north:shared : ✗ [DQ:content_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/role.txt)" = north:shared'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/role.txt contains north:shared : ✗ [DQ:content_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/role.txt)" = north:shared'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/role.txt contains north:shared : ✗ [DQ:content_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
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
