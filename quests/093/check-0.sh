set -euo pipefail
cd ~/quest
dq_fallback_output=$(mktemp) || {
  dq_fallback_status=$?
  printf '%s\n' 'The supplied platform input or observation could not be read: ✗ [DQ:probe_0_0]' >&2
  exit "$dq_fallback_status"
}
trap 'rm -f "$dq_fallback_output"' EXIT
set +e
(
set -e
set -euo pipefail
cd ~/quest
source platform.env
if ! curl -fsS "$VAULT_ADDR/v1/sys/init" 2>/dev/null | jq -e '.initialized == true' >/dev/null 2>&1; then
  printf '%s\n' 'sys/init initialized = true: ✗ [DQ:init]'
  exit 1
fi

) >"$dq_fallback_output" 2>&1
dq_fallback_status=$?
set -e
cat "$dq_fallback_output"
if [ "$dq_fallback_status" -ne 0 ] && ! grep -Eq '\[DQ:(init)\]' "$dq_fallback_output"; then
  printf '%s\n' 'The supplied platform input or observation could not be read: ✗ [DQ:probe_0_0]'
fi
rm -f "$dq_fallback_output"
trap - EXIT
if [ "$dq_fallback_status" -ne 0 ]; then
  exit "$dq_fallback_status"
fi
