set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu state list | grep -Fx local_file.release >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat release.txt)" = release-30
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
