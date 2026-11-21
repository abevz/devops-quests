set -euo pipefail
cd ~/quest
if ! kubectl rollout status deployment/relay --timeout=3s >/dev/null 2>&1 ||
   ! test "$(timeout 4s kubectl exec deployment/relay -c worker -- printenv RELEASE 2>/dev/null)" = release-30; then
  printf '%s\n' 'The relay rollout or running release is incomplete: ✗ [DQ:consumer_release]'
  exit 1
fi
if ! test "$(timeout 4s kubectl exec deployment/relay -c worker -- wget -qO- -T 3 http://relay:8080/ 2>/dev/null)" = signalrail; then
  printf '%s\n' 'The relay Service does not return its expected HTTP response: ✗ [DQ:service_http]'
  exit 1
fi
