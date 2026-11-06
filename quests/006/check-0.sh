set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu state list | grep -Fx docker_container.worker >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
docker inspect rail-worker | jq -e '.[0].State.Running' >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
