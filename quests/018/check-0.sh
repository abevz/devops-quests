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
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/board)" = '"'"'station=app1 route=north slots=3'"'"''
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app1, /srv/site/board contains station=app1 route=north slots=3 : ✗ [DQ:content_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/board)" = '"'"'station=app2 route=north slots=3'"'"''
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/board contains station=app2 route=north slots=3 : ✗ [DQ:content_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/board)" = '"'"'station=app3 route=north slots=3'"'"''
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/board contains station=app3 route=north slots=3 : ✗ [DQ:content_3]'
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
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/board)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app1, /srv/site/board has mode 0644 : ✗ [DQ:mode_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/board)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/board has mode 0644 : ✗ [DQ:mode_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/board)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/board has mode 0644 : ✗ [DQ:mode_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
