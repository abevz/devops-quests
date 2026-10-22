set -euo pipefail
cd ~/quest
tofu state list | grep -Fx module.notice.local_file.notice >/dev/null
test "$(cat north.txt)" = north-ready
test "$(tofu output -raw message)" = north-ready
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
