set -euo pipefail
cd ~/quest
test "$(cat release.txt)" = release-20
test "$(tofu output -raw release)" = release-20
tofu state list | grep -Fx local_file.release
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
