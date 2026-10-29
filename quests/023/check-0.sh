set -euo pipefail
cd ~/quest
failed=0
if ! tofu state list 2>/dev/null | grep -Fx 'module.stations["south"].local_file.notice' >/dev/null; then
  printf '%s\n' 'tofu state list ∋ module.stations["south"].local_file.notice: ✗'
  failed=1
fi
if ! tofu state list 2>/dev/null | grep -Fx 'module.stations["north"].local_file.notice' >/dev/null; then
  printf '%s\n' 'tofu state list ∋ module.stations["north"].local_file.notice: ✗'
  failed=1
fi
if ! test "$(cat south.txt 2>/dev/null)" = south-ready; then
  printf '%s\n' 'south.txt = south-ready: ✗'
  failed=1
fi
if ! test "$(cat north.txt 2>/dev/null)" = north-ready; then
  printf '%s\n' 'north.txt = north-ready: ✗'
  failed=1
fi
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan -input=false -detailed-exitcode -no-color → 0: ✗'
  failed=1
fi
exit "$failed"
