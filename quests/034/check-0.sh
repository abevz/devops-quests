set -euo pipefail
cd ~/quest
kubectl rollout status deployment/board --timeout=3s
kubectl get deployment board -o json | jq -e '.spec.template.spec.containers[0].resources | .requests.cpu=="100m" and .limits.cpu=="300m"' >/dev/null
pod=$(kubectl get pods -l app=board -o jsonpath='{.items[0].metadata.name}')
test "$(kubectl exec "$pod" -- wget -qO- http://127.0.0.1:8080)" = north
kubectl get deployment board -o json | jq -e '.spec.replicas==1 and .spec.template.spec.containers[0].resources.requests.memory=="16Mi" and .spec.template.spec.containers[0].resources.limits.memory=="64Mi"' >/dev/null
