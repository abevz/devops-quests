set -euo pipefail
cd ~/quest
source platform.env
kubectl create secret docker-registry registry-pull --docker-server="$REGISTRY" --docker-username="$REGISTRY_USER" --docker-password="$REGISTRY_PASSWORD" --dry-run=client -o json > registry-pull.json
kubectl apply -f registry-pull.json >/dev/null
kubectl rollout restart deployment/board
kubectl rollout status deployment/board --timeout=90s
