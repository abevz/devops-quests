set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
python3 -I - <<'DQ_PROPERTY'
import re
import subprocess
import sys
for value in ('0', '7', '2.5'):
    result = subprocess.run(['tofu', 'plan', '-input=false', '-no-color', '-var=departures=' + value], capture_output=True, text=True)
    text = result.stdout + result.stderr
    with open('invalid-plan.txt', 'w') as report:
        report.write(text)
    text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', text)
    # OpenTofu can wrap diagnostic text and prefix continuation lines with a bar.
    text = ' '.join(text.replace('│', ' ').split())
    if result.returncode == 0 or not re.search(r'\bdepartures must be an integer from 1 to 6\b', text):
        sys.exit(1)
DQ_PROPERTY
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat timetable.txt)" = 3
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu output -json departures | jq -e '.==3' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
