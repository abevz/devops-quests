set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
test "$(curl -fsS --max-time 3 http://app1-${DQ_NAMESPACE#dq-}:8080)" = north-ready
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(curl -fsS --max-time 3 http://app2-${DQ_NAMESPACE#dq-}:8080)" = north-ready
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(curl -fsS --max-time 3 http://app3-${DQ_NAMESPACE#dq-}:8080)" = north-ready
)
[ $? -eq 0 ] || failed=1
exit "$failed"
