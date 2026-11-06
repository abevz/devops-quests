set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu state list | grep -Fx local_file.release
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat release.txt)" = north-r16
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu output -json release | jq -e '.route=="north" and .revision==16 and .targets==["app1","app2","app3"]' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
