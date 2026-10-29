set -euo pipefail
cd ~/quest
failed=0
if ! tofu state list 2>/dev/null | grep -Fx local_file.release >/dev/null; then
  printf '%s\n' 'tofu state list ∋ local_file.release: ✗ [DQ:state]'
  failed=1
fi
if ! test "$(cat release.txt 2>/dev/null)" = release-90; then
  printf '%s\n' 'release.txt = release-90: ✗ [DQ:file]'
  failed=1
fi
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan -input=false -detailed-exitcode -no-color → 0: ✗ [DQ:plan]'
  failed=1
fi
exit "$failed"
