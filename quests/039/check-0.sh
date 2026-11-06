set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
for value in 0 7 2.5; do
 if tofu plan -input=false -no-color -var="departures=$value" > invalid-plan.txt 2>&1; then exit 1; fi
 grep -q 'departures must be an integer from 1 to 6' invalid-plan.txt
done
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
