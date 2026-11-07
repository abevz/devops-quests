set -euo pipefail
cd ~/quest
kubectl rollout status deployment/relay --timeout=3s >/dev/null
test "$(kubectl exec deployment/relay -c worker -- printenv RELEASE)" = release-60
