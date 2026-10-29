set -euo pipefail
cd ~/quest
failed=0
if ! kubectl rollout status deployment/relay --timeout=3s >/dev/null 2>&1; then
  printf '%s\n' 'deployment/relay rollout complete: ✗'; failed=1
fi
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/relay -- printenv RELEASE 2>/dev/null)" = release-90; then
  printf '%s\n' 'deployment/relay RELEASE = release-90: ✗'; failed=1
fi
exit "$failed"
