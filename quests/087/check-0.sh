set -euo pipefail
cd ~/quest
test "$(cat notice.txt)" = north-ready
tofu state list | grep -Fx local_file.notice >/dev/null
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
