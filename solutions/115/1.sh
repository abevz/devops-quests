set -euo pipefail
cd ~/quest
kubectl scale deployment blue --replicas=3
kubectl scale deployment green --replicas=1
kubectl rollout status deployment/blue --timeout=90s
kubectl rollout status deployment/green --timeout=90s
