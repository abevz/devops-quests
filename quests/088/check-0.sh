set -euo pipefail
cd ~/quest
kubectl rollout status deployment/relay --timeout=3s >/dev/null
kubectl get deployment relay -o json | jq -e '.spec.template.spec.containers[0].resources.limits.memory=="96Mi"' >/dev/null
