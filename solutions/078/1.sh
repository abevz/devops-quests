set -euo pipefail
cd ~/quest
kubectl scale deployment board --replicas=1
kubectl rollout status deployment/board --timeout=90s
