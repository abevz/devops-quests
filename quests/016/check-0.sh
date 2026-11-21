set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu state list | grep -Fx local_file.release || {
  code=$?
  printf '%s\n' 'OpenTofu tracks local_file.release: ✗ [DQ:condition_0]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat release.txt)" = north-r16 || {
  code=$?
  printf '%s\n' 'release.txt contains north-r16: ✗ [DQ:condition_1]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu output -json release | jq -e '.route=="north" and .revision==16 and .targets==["app1","app2","app3"]' >/dev/null || {
  code=$?
  printf '%s\n' 'release output is the expected JSON object: ✗ [DQ:condition_2]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null || {
  code=$?
  printf '%s\n' 'OpenTofu detailed plan exits with 0: ✗ [DQ:condition_3]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
exit "$failed"
