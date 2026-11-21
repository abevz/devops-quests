set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu console <<< 'type(var.station)' | grep -Fx string || {
  code=$?
  printf '%s\n' 'station input is a string: ✗ [DQ:condition_0]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu state list | grep -Fx local_file.notice || {
  code=$?
  printf '%s\n' 'OpenTofu tracks local_file.notice: ✗ [DQ:condition_1]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat notice.txt)" = north:4 || {
  code=$?
  printf '%s\n' 'notice.txt contains north:4: ✗ [DQ:condition_2]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(tofu output -raw station)" = north || {
  code=$?
  printf '%s\n' 'station output is north: ✗ [DQ:condition_3]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu output -json departures | jq -e '.==4' >/dev/null || {
  code=$?
  printf '%s\n' 'departures output is numeric 4: ✗ [DQ:condition_4]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null || {
  code=$?
  printf '%s\n' 'OpenTofu detailed plan exits with 0: ✗ [DQ:condition_5]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
exit "$failed"
