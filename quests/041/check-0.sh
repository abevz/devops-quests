set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
failed=0
if ! git -C repository fetch origin main release-candidate >/dev/null 2>&1; then
  printf '%s\n' 'git fetch origin main release-candidate: ✗ [DQ:fetch]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
failed=0
if ! test "$(git -C repository branch --show-current 2>/dev/null)" = main; then
  printf '%s\n' 'repository branch = main: ✗ [DQ:branch]'
  failed=1
fi

if ! test -z "$(git -C repository status --porcelain 2>/dev/null)"; then
  printf '%s\n' 'git status --porcelain = empty: ✗ [DQ:clean]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
source platform.env
python3 -I - <<'DQ_NOTICE'
import subprocess,sys
failed=False
for ref,marker in [('origin/main','origin_file'),('HEAD','head_file')]:
    result=subprocess.run(['git','-C','repository','show',ref+':notice.txt'],capture_output=True)
    if result.returncode or result.stdout.replace(b'\r\n',b'\n').rstrip(b'\n')!=b'north-41':
        print(f'{ref}:notice.txt = north-41: ✗ [DQ:{marker}]')
        failed=True
sys.exit(int(failed))
DQ_NOTICE
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_2]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
failed=0
if ! test -s baseline-commit || ! git -C repository merge-base --is-ancestor "$(cat baseline-commit 2>/dev/null)" origin/main 2>/dev/null; then
  printf '%s\n' 'baseline-commit → origin/main: ✗ [DQ:ancestor]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
failed=0
if ! test "$(git -C repository rev-parse HEAD 2>/dev/null)" = "$(git -C repository rev-parse origin/main 2>/dev/null)" || ! git -C repository rev-parse --verify HEAD >/dev/null 2>&1; then
  printf '%s\n' 'HEAD = origin/main: ✗ [DQ:head]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
