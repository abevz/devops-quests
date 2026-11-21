set -euo pipefail
cd ~/quest
kubectl rollout status deployment/relay --timeout=3s >/dev/null || {
  code=$?
  printf '%s\n' 'Deployment relay rollout is complete: ✗ [DQ:condition_0]' >&2
  exit "$code"
}
