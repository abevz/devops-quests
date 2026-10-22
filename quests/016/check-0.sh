set -euo pipefail
cd ~/quest
tofu output -json release | jq -e '.route=="north" and .revision==16 and .targets==["app1","app2","app3"]' >/dev/null
test "$(cat release.txt)" = north-r16
tofu state list | grep -Fx local_file.release
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
