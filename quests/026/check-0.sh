set -euo pipefail
cd ~/quest
failed=0
if ! tofu state list 2>/dev/null | grep -Fx docker_container.worker >/dev/null; then
  printf '%s\n' 'tofu state list ∋ docker_container.worker: ✗ [DQ:condition_0]'
  failed=1
fi
if ! test "$(cat original-id 2>/dev/null)" = "$(docker inspect rail-worker --format '{{.Id}}' 2>/dev/null)" || ! test -s original-id; then
  printf '%s\n' 'original-id = docker inspect rail-worker --format {{.Id}}: ✗ [DQ:condition_1]'
  failed=1
fi
if ! test -s original-id || ! test "$(tofu show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | select(.address=="docker_container.worker") | .values.id' 2>/dev/null)" = "$(cat original-id 2>/dev/null)"; then
  printf '%s\n' 'tofu show -json docker_container.worker id = original-id: ✗ [DQ:condition_2]'
  failed=1
fi
if ! docker inspect rail-worker 2>/dev/null | jq -e '.[0].State.Running' >/dev/null 2>&1; then
  printf '%s\n' 'rail-worker State.Running = true: ✗ [DQ:condition_3]'
  failed=1
fi
if ! docker inspect rail-worker 2>/dev/null | jq -e '.[0].State.Paused == false' >/dev/null 2>&1; then
  printf '%s\n' 'rail-worker State.Paused = false: ✗ [DQ:condition_4]'
  failed=1
fi
exit "$failed"
