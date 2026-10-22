set -euo pipefail
cd ~/quest
test "$(cat notice.txt)" = north:4
test "$(tofu output -raw station)" = north
tofu output -json departures | jq -e '.==4' >/dev/null
tofu console <<< 'type(var.station)' | grep -Fx string
tofu state list | grep -Fx local_file.notice
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
