set -euo pipefail
cd ~/quest
tofu state list | grep -Fx docker_container.worker >/dev/null
docker inspect rail-worker | jq -e '.[0].State.Running' >/dev/null
