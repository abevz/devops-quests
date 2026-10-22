set -euo pipefail
cd ~/quest
kubectl set image deployment/relay worker="$(jq -er .image release-manifest.json)"
kubectl rollout status deployment/relay --timeout=90s
