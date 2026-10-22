set -euo pipefail
cd ~/quest
kubectl rollout status deployment/relay --timeout=3s >/dev/null
