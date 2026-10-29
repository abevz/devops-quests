set -euo pipefail
cd ~/quest
failed=0
if ! test "$(tofu output -raw north_id 2>/dev/null)" = "$(cat /run/dq/facts/0/original-north-id 2>/dev/null)" || ! test -s /run/dq/facts/0/original-north-id; then
  printf '%s\n' 'north_id = /run/dq/facts/0/original-north-id: ✗ [DQ:condition_0]'
  failed=1
fi
if ! test "$(cat north.txt 2>/dev/null)" = north-71; then
  printf '%s\n' 'north.txt = north-71: ✗ [DQ:condition_1]'
  failed=1
fi
if ! test "$(cat south.txt 2>/dev/null)" = south-71; then
  printf '%s\n' 'south.txt = south-71: ✗ [DQ:condition_2]'
  failed=1
fi
if ! test "$(tofu state list 2>/dev/null | sort)" = "$(printf '%s\n' local_file.north local_file.south | sort)"; then
  printf '%s\n' 'tofu state list = {local_file.north, local_file.south}: ✗ [DQ:condition_3]'
  failed=1
fi
if ! jq -e '(.resource_changes|length)==2' recovery-plan.json >/dev/null 2>&1; then
  printf '%s\n' 'recovery-plan.json resource_changes length = 2: ✗ [DQ:condition_4]'
  failed=1
fi
if ! jq -e 'any(.resource_changes[];.address=="local_file.north" and .change.actions==["no-op"])' recovery-plan.json >/dev/null 2>&1; then
  printf '%s\n' 'recovery-plan.json local_file.north actions = ["no-op"]: ✗ [DQ:condition_5]'
  failed=1
fi
if ! jq -e 'any(.resource_changes[];.address=="local_file.south" and .change.actions==["create"])' recovery-plan.json >/dev/null 2>&1; then
  printf '%s\n' 'recovery-plan.json local_file.south actions = ["create"]: ✗ [DQ:condition_6]'
  failed=1
fi
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan -input=false -detailed-exitcode -no-color → 0: ✗ [DQ:condition_7]'
  failed=1
fi
exit "$failed"
