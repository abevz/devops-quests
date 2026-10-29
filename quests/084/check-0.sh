set -euo pipefail
cd ~/quest
failed=0
if ! tofu state list 2>/dev/null | grep -Fx module.station.docker_container.worker >/dev/null; then
  printf '%s\n' 'tofu state list ∋ module.station.docker_container.worker: ✗ [DQ:condition_0]'
  failed=1
fi
if ! test -s original-id || ! test "$(tofu output -raw worker_id 2>/dev/null)" = "$(cat original-id 2>/dev/null)"; then
  printf '%s\n' 'worker_id = original-id: ✗ [DQ:condition_1]'
  failed=1
fi
if ! test -s original-id || ! test "$(tofu show -json 2>/dev/null | jq -r '.values.root_module.child_modules[]?.resources[]? | select(.address=="module.station.docker_container.worker") | .values.id' 2>/dev/null)" = "$(cat original-id 2>/dev/null)"; then
  printf '%s\n' 'tofu show -json module.station.docker_container.worker id = original-id: ✗ [DQ:condition_2]'
  failed=1
fi
if ! test -s original-id || ! test "$(docker inspect rail-worker --format '{{.Id}}' 2>/dev/null)" = "$(cat original-id 2>/dev/null)"; then
  printf '%s\n' 'docker inspect rail-worker --format {{.Id}} = original-id: ✗ [DQ:condition_3]'
  failed=1
fi
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan -input=false -detailed-exitcode -no-color → 0: ✗ [DQ:condition_4]'
  failed=1
fi
exit "$failed"
