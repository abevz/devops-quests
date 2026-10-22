set -euo pipefail
cd ~/quest
tofu state list | grep -Fx 'module.stations["south"].local_file.notice' >/dev/null
tofu state list | grep -Fx 'module.stations["north"].local_file.notice' >/dev/null
test "$(cat south.txt)" = south-ready
test "$(cat north.txt)" = north-ready
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
