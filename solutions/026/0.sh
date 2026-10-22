set -euo pipefail
cd ~/quest
tofu import docker_container.worker "$(cat original-id)"
docker unpause rail-worker
