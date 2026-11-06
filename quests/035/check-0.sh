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
set +e
(
set -e
test "$(grep -Ec '^app[123][[:space:]]+:.*unreachable=0.*failed=0' probe.log)" = 3
)
dq_action_rc=$?
set -e
if [ "$dq_action_rc" -ne 0 ]; then
if ! grep -Eq '^app1[[:space:]]+:.*unreachable=0.*failed=0' probe.log 2>/dev/null; then
printf '%s\n' 'Workstation probe.log: app1 must report unreachable=0 and failed=0. ✗ [DQ:recap_1]'
fi
if ! grep -Eq '^app2[[:space:]]+:.*unreachable=0.*failed=0' probe.log 2>/dev/null; then
printf '%s\n' 'Workstation probe.log: app2 must report unreachable=0 and failed=0. ✗ [DQ:recap_2]'
fi
if ! grep -Eq '^app3[[:space:]]+:.*unreachable=0.*failed=0' probe.log 2>/dev/null; then
printf '%s\n' 'Workstation probe.log: app3 must report unreachable=0 and failed=0. ✗ [DQ:recap_3]'
fi
printf '%s\n' 'Workstation probe.log must contain the three required healthy-host recaps : ✗ [DQ:recap_count]'
exit 1
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
