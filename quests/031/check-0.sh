set -euo pipefail
cd ~/quest
kubectl rollout status deployment/reader --timeout=3s
pod=$(kubectl get pods -l app=reader -o jsonpath='{.items[0].metadata.name}')
test "$(kubectl exec "$pod" -- cat /tmp/route)" = north
kubectl get deployment reader -o json | jq -e '.spec.template.spec.containers[0].env[0].valueFrom.secretKeyRef=={"name":"station","key":"route"}' >/dev/null
