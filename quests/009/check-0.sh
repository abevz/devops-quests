set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu state list | grep -Fx local_file.notice >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat notice.txt)" = north-ready
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
