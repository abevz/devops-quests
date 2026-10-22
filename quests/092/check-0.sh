set -euo pipefail
cd ~/quest
test "$(sha256sum safe-state.json | cut -d' ' -f1)" = "$(cat /run/dq/facts/0/safe-state.sha256)"
jq -e '.resources|any(.module=="module.north" and .type=="local_file" and .name=="ledger")' safe-state.json >/dev/null
test "$(tofu state list)" = module.station.local_file.ledger
test "$(tofu output -raw ledger_id)" = "$(cat /run/dq/facts/0/original-id)"
test "$(cat ledger.txt)" = north-92
jq -e '.resource_changes|length==1 and all(.[];.change.actions==["no-op"])' recovery-plan.json >/dev/null
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
