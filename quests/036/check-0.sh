set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
jq -e '.resource_changes[]|select(.address=="local_file.ledger")|.change.actions|index("delete")!=null and index("create")!=null' rejected-plan.json >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat ledger.txt)" = revision-36
)
[ $? -eq 0 ] || failed=1
(
set -e
test ! -e retired-ledger.txt
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(tofu output -raw ledger_id)" = "$(cat original-id)"
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
