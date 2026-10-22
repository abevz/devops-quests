set -euo pipefail
cd ~/quest
grep -Fx 'route must equal north' diagnosis.txt
kubectl rollout status deployment/route-worker --timeout=3s
test "$(kubectl exec deploy/route-worker -- printenv ROUTE)" = north
