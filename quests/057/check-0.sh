set -euo pipefail
cd ~/quest
test "$(kubectl get pvc spool -o jsonpath='{.status.phase}')" = Bound
kubectl rollout status deployment/relay --timeout=3s >/dev/null
