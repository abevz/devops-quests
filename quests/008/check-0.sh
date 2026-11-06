set -euo pipefail
cd ~/quest
dq_group_failed=0
set +e
(
set -e
test "$(curl -fsS --max-time 3 http://app1-${DQ_NAMESPACE#dq-}:8080)" = north-ready
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'The HTTP banner on app1:8080 returns north-ready : ✗ [DQ:http_1]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app2-${DQ_NAMESPACE#dq-}:8080)" = north-ready
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'The HTTP banner on app2:8080 returns north-ready : ✗ [DQ:http_2]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app3-${DQ_NAMESPACE#dq-}:8080)" = north-ready
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'The HTTP banner on app3:8080 returns north-ready : ✗ [DQ:http_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
