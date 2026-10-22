set -euo pipefail
cd ~/quest
tofu state list | grep -Fx local_file.ledger >/dev/null
test "$(tofu show -json | jq -r ' .values.root_module.resources[]|select(.address=="local_file.ledger")|.values.id')" = "$(cat original-id)"
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
