set -euo pipefail
cd ~/quest
jq '.spec.limits[0].default.cpu="200m" | .spec.limits[0].defaultRequest.cpu="100m"' defaults.json > /tmp/fixed-defaults.json
cp /tmp/fixed-defaults.json defaults.json
kubectl apply -f defaults.json
kubectl rollout restart deployment/board
kubectl rollout status deployment/board --timeout=90s
