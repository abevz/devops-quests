set -euo pipefail
cd ~/quest
test "$(tofu state list)" = "$(cat original-addresses)"
test "$(tofu output -json ids)" = "$(cat original-ids.json)"
test "$(cat north.txt)" = north-47
test "$(cat depot.txt)" = depot-47
tofu output -json contracts | jq -e --arg checksum "$(sha256sum north.txt | cut -d' ' -f1)" '.station.release==2 and .station.checksum==$checksum and .depot.release==1' >/dev/null
jq -e '.configuration.root_module.module_calls.station.source=="./modules/v2" and .configuration.root_module.module_calls.depot.source=="./modules/v1" and all(.resource_changes[]; .change.actions==["no-op"])' upgrade-plan.json >/dev/null
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
