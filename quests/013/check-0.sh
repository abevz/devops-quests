set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu console <<< 'type(var.station)' | grep -Fx string
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu state list | grep -Fx local_file.notice
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat notice.txt)" = north:4
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(tofu output -raw station)" = north
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu output -json departures | jq -e '.==4' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
