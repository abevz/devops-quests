set -euo pipefail
cd ~/quest
test "$(kubectl exec deployment/relay -c worker -- printenv ROUTE)" = north || {
  code=$?
  printf '%s\n' 'Running worker exposes ROUTE=north: ✗ [DQ:condition_0]' >&2
  exit "$code"
}
