set -euo pipefail
cd ~/quest
failed=0
if ! tofu state list 2>/dev/null | grep -Fx local_file.release >/dev/null; then
  printf '%s\n' 'tofu state list: local_file.release missing: ✗'; failed=1
fi
if ! test "$(cat release.txt 2>/dev/null)" = release-81; then
  printf '%s\n' 'release.txt = release-81: ✗'; failed=1
fi
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan exits 0: ✗'; failed=1
fi
exit "$failed"
