set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set +e
(
set -e
tofu state list | grep -Fx local_file.ledger >/dev/null
test "$(tofu show -json | jq -r ' .values.root_module.resources[]|select(.address=="local_file.ledger")|.values.id')" = "$(cat original-id)"
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The renamed file state could not be verified: ✗ [DQ:move_state]' >&2
  exit "$code"
fi
if ! test "$(cat original-id)" = "$(cat /run/dq/facts/0/original-id)"; then
 printf '%s\n' 'Both linked ledger identities and the original content must be preserved: ✗ [DQ:move_identity]'
 exit 1
fi
if ! tofu show -json | jq -e --arg uid "$(cat /run/dq/facts/0/original-identity)" --arg message "$(cat notice.txt)" '.values.root_module.resources[] | select(.address=="terraform_data.ledger" and .mode=="managed" and .type=="terraform_data") | .values.id==$uid and .values.output.message==$message' >/dev/null; then
 printf '%s\n' 'Both linked ledger identities and the original content must be preserved: ✗ [DQ:move_identity]'
 exit 1
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The address migration plan did not complete without changes: ✗ [DQ:move_plan]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
