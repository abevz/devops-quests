set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
for bad in 0 4 1.5; do if tofu plan -input=false -var="replicas=$bad" >/dev/null 2>&1; then exit 1; fi; done
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat replicas.txt)" = 2
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -var=replicas=2 -detailed-exitcode >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
