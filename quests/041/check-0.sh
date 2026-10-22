set -euo pipefail
cd ~/quest
source platform.env
git -C repository fetch origin main release-candidate >/dev/null 2>&1
test "$(git -C repository branch --show-current)" = main
test "$(git -C repository show origin/main:notice.txt)" = north-41
test "$(git -C repository show HEAD:notice.txt)" = north-41
git -C repository merge-base --is-ancestor "$(cat baseline-commit)" origin/main
test -z "$(git -C repository status --porcelain)"
test "$(git -C repository rev-parse HEAD)" = "$(git -C repository rev-parse origin/main)"
