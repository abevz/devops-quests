set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
test "$(cat safety-check.txt)" = 'healthy fleet checked'
)
[ $? -eq 0 ] || failed=1
(
set -e
grep -q UNREACHABLE probe.log
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(grep -Ec '^app[123][[:space:]]+:.*unreachable=0.*failed=0' probe.log)" = 3
)
[ $? -eq 0 ] || failed=1
exit "$failed"
