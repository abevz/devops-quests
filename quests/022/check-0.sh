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
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'grep -qx station=app1 /srv/site/message'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app1, /srv/site/message contains the complete line station=app1 : ✗ [DQ:identity_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'grep -qx station=app2 /srv/site/message'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/message contains the complete line station=app2 : ✗ [DQ:identity_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'grep -qx station=app3 /srv/site/message'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/message contains the complete line station=app3 : ✗ [DQ:identity_3]'
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
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'grep -qx route=north /srv/site/message'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app1, /srv/site/message contains the complete line route=north : ✗ [DQ:route_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'grep -qx route=north /srv/site/message'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/message contains the complete line route=north : ✗ [DQ:route_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'grep -qx route=north /srv/site/message'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/message contains the complete line route=north : ✗ [DQ:route_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
