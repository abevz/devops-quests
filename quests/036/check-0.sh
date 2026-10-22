set -euo pipefail
cd ~/quest
test "$(cat ledger.txt)" = revision-36
test ! -e retired-ledger.txt
test "$(tofu output -raw ledger_id)" = "$(cat original-id)"
jq -e '.resource_changes[]|select(.address=="local_file.ledger")|.change.actions|index("delete")!=null and index("create")!=null' rejected-plan.json >/dev/null
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
