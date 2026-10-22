set -euo pipefail
cd ~/quest
test "$(cat safety-check.txt)" = 'healthy fleet checked'
grep -q UNREACHABLE probe.log
test "$(grep -Ec '^app[123][[:space:]]+:.*unreachable=0.*failed=0' probe.log)" = 3
