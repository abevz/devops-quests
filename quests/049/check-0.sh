set -euo pipefail
cd ~/quest
source platform.env
test "$(kubectl get deployment board -o jsonpath='{.spec.template.spec.containers[0].image}')" = "$PRIVATE_IMAGE"
kubectl get deployment board -o json | jq -e '.spec.template.spec.containers[0].imagePullPolicy=="Always" and .spec.template.spec.imagePullSecrets==[{"name":"registry-pull"}]' >/dev/null
kubectl rollout status deployment/board --timeout=3s >/dev/null
digest=$(printf %s "$PRIVATE_IMAGE" | cut -d@ -f2)
kubectl get pods -l app=board -o json | jq -e --arg digest "$digest" 'any(.items[]; .metadata.deletionTimestamp==null and .status.phase=="Running" and any(.status.containerStatuses[]?; .ready==true and (.imageID|contains($digest))))' >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- http://127.0.0.1:8080)" = north-49
