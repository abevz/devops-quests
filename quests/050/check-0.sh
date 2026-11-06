set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository branch --show-current)" = main
test "$(git -C repository rev-parse HEAD)" = "$(git -C repository rev-parse origin/main)"
test -z "$(git -C repository status --porcelain)"
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
git -C repository show origin/main:manifests/route.yaml | python3 -c 'import sys,yaml; assert yaml.safe_load(sys.stdin)["data"]["index.html"]=="north-50"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
git -C repository merge-base --is-ancestor "$(cat baseline-commit)" origin/main
)
[ $? -eq 0 ] || failed=1
exit "$failed"
