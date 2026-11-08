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
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
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
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_1]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
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
