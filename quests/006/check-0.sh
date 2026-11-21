set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu state list | grep -Fx docker_container.worker >/dev/null || {
  code=$?
  printf '%s\n' 'OpenTofu tracks docker_container.worker: ✗ [DQ:condition_0]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
docker inspect rail-worker | jq -e '.[0].State.Running' >/dev/null || {
  code=$?
  printf '%s\n' 'Container rail-worker is running: ✗ [DQ:condition_1]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
exit "$failed"
