set -euo pipefail
cd ~/quest
test "$(tofu output -raw north_id)" = "$(cat /run/dq/facts/0/original-north-id)"
test "$(cat north.txt)" = north-71
test "$(cat south.txt)" = south-71
test "$(tofu state list)" = "$(printf '%s\n' local_file.north local_file.south)"
jq -e '(.resource_changes|length)==2 and any(.resource_changes[];.address=="local_file.north" and .change.actions==["no-op"]) and any(.resource_changes[];.address=="local_file.south" and .change.actions==["create"])' recovery-plan.json >/dev/null
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
