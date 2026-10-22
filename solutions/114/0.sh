set -euo pipefail
cd ~/quest
kubectl patch deployment reader --type=json -p '[{"op": "replace", "path": "/spec/template/spec/volumes/0/projected/sources/0/serviceAccountToken/audience", "value": "https://kubernetes.default.svc.cluster.local"}]'
kubectl rollout status deployment/reader --timeout=90s
