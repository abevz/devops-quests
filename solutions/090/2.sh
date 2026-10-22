set -euo pipefail
cd ~/quest
kubectl set env deployment/relay RELEASE=release-90
kubectl rollout status deployment/relay --timeout=90s
