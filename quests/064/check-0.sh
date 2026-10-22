set -euo pipefail
cd ~/quest
tofu output -json routes | jq -e '.=={depot:"./depot.txt",junction:"./junction.txt"}' >/dev/null
test "$(cat depot.txt)" = north:depot
test "$(cat junction.txt)" = north:junction
test "$(tofu state list)" = "$(cat original-addresses)"
jq -e '.configuration.root_module.module_calls.station.expressions.region.references==["local.region"] and (.resource_changes|length)==2 and all(.resource_changes[];.change.actions==["delete","create"])' fanout-plan.json >/dev/null
tofu plan -detailed-exitcode -input=false -no-color >/dev/null
