set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
grep -Fx 'route must equal north' diagnosis.txt || {
  code=$?
  printf '%s\n' 'diagnosis.txt contains the exact route error: ✗ [DQ:condition_0]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/route-worker --timeout=3s || {
  code=$?
  printf '%s\n' 'Deployment route-worker rollout is complete: ✗ [DQ:condition_1]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deploy/route-worker -c worker -- printenv ROUTE)" = north || {
  code=$?
  printf '%s\n' 'Running worker exposes ROUTE=north: ✗ [DQ:condition_2]' >&2
  exit "$code"
}
)
[ $? -eq 0 ] || failed=1
exit "$failed"
