set -euo pipefail
cd ~/quest
test "$(cat work/route.txt)" = north
test -f work/.prepared
tofu state list | grep -Fx terraform_data.directory
tofu state list | grep -Fx terraform_data.marker
tofu graph | grep -E 'marker.*->.*directory' >/dev/null
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
