set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
jq -e '.configuration.root_module.module_calls.station.expressions.region.references==["local.region"]' fanout-plan.json >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
jq -e '(.resource_changes|length)==2 and all(.resource_changes[];.change.actions==["delete","create"])' fanout-plan.json >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(tofu state list)" = "$(cat original-addresses)"
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat depot.txt)" = north:depot
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat junction.txt)" = north:junction
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu output -json routes | jq -e '.=={depot:"./depot.txt",junction:"./junction.txt"}' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -detailed-exitcode -input=false -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
