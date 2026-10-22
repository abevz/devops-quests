set -euo pipefail
cd ~/quest
tofu state list | grep -Fx docker_container.worker >/dev/null
test "$(cat original-id)" = "$(docker inspect rail-worker --format '{{.Id}}')"
docker inspect rail-worker | jq -e '.[0].State.Running and (.[0].State.Paused|not)' >/dev/null

