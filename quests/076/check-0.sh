set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu validate -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
sha256sum -c /run/dq/facts/0/original-module.sha256 >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(tofu state list | wc -l)" = 2
test "$(tofu state list)" = "$(printf '%s\n' module.north.local_file.route module.south.local_file.route)"
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat north.txt)" = dispatch:north
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat south.txt)" = dispatch:north:south
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu output -json routes | jq -e '.=={north:"dispatch:north",south:"dispatch:north:south"}' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
