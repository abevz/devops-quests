set -euo pipefail
cd ~/quest
tofu validate -no-color >/dev/null
test "$(cat north.txt)" = dispatch:north
test "$(cat south.txt)" = dispatch:north:south
tofu output -json routes | jq -e '.=={north:"dispatch:north",south:"dispatch:north:south"}' >/dev/null
test "$(tofu state list | wc -l)" = 2
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
sha256sum -c /run/dq/facts/0/original-module.sha256 >/dev/null
test "$(tofu state list)" = "$(printf '%s\n' module.north.local_file.route module.south.local_file.route)"
