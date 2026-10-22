set -euo pipefail
cd ~/quest
tofu state list | grep -Fx module.station.docker_container.worker >/dev/null
test "$(tofu output -raw worker_id)" = "$(cat original-id)"
test "$(docker inspect rail-worker --format '{{.Id}}')" = "$(cat original-id)"
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
