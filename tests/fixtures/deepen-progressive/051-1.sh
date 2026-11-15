set -euo pipefail
cd ~/quest
kubectl set env deployment/backup ROUTE=north
kubectl rollout status deployment/backup --timeout=90s
