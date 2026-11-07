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
set -euo pipefail
cd ~/quest
source platform.env
if ! git -C repository fetch origin main >/dev/null 2>&1; then
  printf '%s\n' 'Published release is unavailable: ✗ [DQ:published]'
  exit 1
fi
manifest=$(git -C repository show origin/main:manifests/route.yaml 2>/dev/null || true)
python3 -I - /dev/fd/3 3<<<"$manifest" <<'DQ_PUBLISHED'
import sys
try:
    import yaml
    with open(sys.argv[1]) as stream:
        document=yaml.safe_load(stream)
    value=document.get('data',{}).get('index.html')
    good=isinstance(value,str) and value.rstrip('\n')=='north-50'
except Exception:
    good=False
if not good:
    print('Published response content is incorrect: ✗ [DQ:published]')
    raise SystemExit(1)
DQ_PUBLISHED
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
