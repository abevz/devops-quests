set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
failed=0
if ! tofu state list 2>/dev/null | grep -Fx 'module.notice.local_file.notice' >/dev/null; then
  printf '%s\n' 'tofu state list ∋ module.notice.local_file.notice: ✗ [DQ:condition_0]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! test "$(cat north.txt 2>/dev/null)" = north-ready; then
  printf '%s\n' 'north.txt = north-ready: ✗ [DQ:condition_1]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! test "$(tofu output -raw message 2>/dev/null)" = north-ready; then
  printf '%s\n' 'tofu output -raw message = north-ready: ✗ [DQ:condition_2]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! tofu state list 2>/dev/null | grep -Fx 'module.notice.local_file.notice' >/dev/null || ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'module.notice.local_file.notice tracked; detailed plan → 0: ✗ [DQ:condition_3]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
