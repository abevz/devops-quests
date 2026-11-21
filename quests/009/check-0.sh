set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu state list | grep -Fx local_file.notice >/dev/null || {
  code=$?
  printf '%s\n' 'OpenTofu state tracks local_file.notice: ✗ [DQ:condition_0]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat notice.txt)" = north-ready || {
  code=$?
  printf '%s\n' 'notice.txt contains north-ready: ✗ [DQ:condition_1]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null || {
  code=$?
  printf '%s\n' 'OpenTofu detailed plan exits with 0: ✗ [DQ:condition_2]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
exit "$failed"
