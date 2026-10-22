set -euo pipefail
cd ~/quest
kubectl rollout status deployment/board --timeout=3s
kubectl get deployment board -o json | jq -e '.spec.replicas==2 and .spec.strategy.rollingUpdate.maxUnavailable==0 and .spec.strategy.rollingUpdate.maxSurge==1 and .status.availableReplicas==2' >/dev/null
for pod in $(kubectl get pods -l app=board -o json | jq -r '.items[]|select(.metadata.deletionTimestamp==null and .status.phase=="Running")|.metadata.name' ); do
 test "$(kubectl exec "$pod" -- wget -qO- http://board:8080)" = north-40
done
kubectl get service board -o json | jq -e '.spec.selector=={"app":"board"} and .spec.ports[0].port==8080 and .spec.ports[0].targetPort==8080' >/dev/null
