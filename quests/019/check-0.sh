set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu state list | grep -Fx terraform_data.directory
tofu state list | grep -Fx terraform_data.marker
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu graph | grep -E 'marker.*->.*directory' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test -f work/.prepared
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat work/route.txt)" = north
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
