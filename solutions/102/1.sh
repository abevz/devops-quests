set -euo pipefail
cd ~/quest
kubectl patch deployment board --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":8080}]'
kubectl rollout status deployment/board --timeout=90s
