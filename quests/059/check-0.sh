set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu state list | grep -Fx local_file.ledger >/dev/null
test "$(tofu show -json | jq -r ' .values.root_module.resources[]|select(.address=="local_file.ledger")|.values.id')" = "$(cat original-id)"
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
