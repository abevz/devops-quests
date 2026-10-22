set -euo pipefail
cd ~/quest
tofu state list | grep -Fx local_file.release >/dev/null
test "$(cat release.txt)" = release-81
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
