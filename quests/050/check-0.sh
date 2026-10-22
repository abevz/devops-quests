set -euo pipefail
cd ~/quest
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository branch --show-current)" = main
git -C repository show origin/main:manifests/route.json | jq -e '.data["index.html"]=="north-50"' >/dev/null
git -C repository merge-base --is-ancestor "$(cat baseline-commit)" origin/main
test "$(git -C repository rev-parse HEAD)" = "$(git -C repository rev-parse origin/main)"
test -z "$(git -C repository status --porcelain)"
