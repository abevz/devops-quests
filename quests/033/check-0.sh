set -euo pipefail
cd ~/quest
test "$(cat east.txt)" = open
tofu output -json routes > current-ids.json
jq -e --slurpfile old original-ids.json '.north==$old[0].north and .south==$old[0].south and (.east|type=="string") and length==3' current-ids.json >/dev/null
tofu state list | grep -Fx 'local_file.route["east"]'
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
test "$(cat north.txt)" = open
test "$(cat south.txt)" = held
