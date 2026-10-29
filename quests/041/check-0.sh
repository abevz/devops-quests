set -euo pipefail
cd ~/quest
source platform.env
failed=0
if ! git -C repository fetch origin main release-candidate >/dev/null 2>&1; then
  printf '%s\n' 'git fetch origin main release-candidate: ✗ [DQ:fetch]'
  failed=1
fi
if ! test "$(git -C repository branch --show-current 2>/dev/null)" = main; then
  printf '%s\n' 'repository branch = main: ✗ [DQ:branch]'
  failed=1
fi
if ! test "$(git -C repository show origin/main:notice.txt 2>/dev/null)" = north-41; then
  printf '%s\n' 'origin/main:notice.txt = north-41: ✗ [DQ:origin_file]'
  failed=1
fi
if ! test "$(git -C repository show HEAD:notice.txt 2>/dev/null)" = north-41; then
  printf '%s\n' 'HEAD:notice.txt = north-41: ✗ [DQ:head_file]'
  failed=1
fi
if ! test -s baseline-commit || ! git -C repository merge-base --is-ancestor "$(cat baseline-commit 2>/dev/null)" origin/main 2>/dev/null; then
  printf '%s\n' 'baseline-commit → origin/main: ✗ [DQ:ancestor]'
  failed=1
fi
if ! test -z "$(git -C repository status --porcelain 2>/dev/null)"; then
  printf '%s\n' 'git status --porcelain = empty: ✗ [DQ:clean]'
  failed=1
fi
if ! test "$(git -C repository rev-parse HEAD 2>/dev/null)" = "$(git -C repository rev-parse origin/main 2>/dev/null)" || ! git -C repository rev-parse --verify HEAD >/dev/null 2>&1; then
  printf '%s\n' 'HEAD = origin/main: ✗ [DQ:head]'
  failed=1
fi
exit "$failed"
