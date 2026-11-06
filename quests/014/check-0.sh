set -euo pipefail
cd ~/quest
failed=0
if ! (
grep -Fx 'route must equal north' diagnosis.txt
); then failed=1; fi
if ! (
kubectl rollout status deployment/route-worker --timeout=3s
); then failed=1; fi
if ! (
test "$(kubectl exec deploy/route-worker -- printenv ROUTE)" = north
); then failed=1; fi
exit "$failed"
