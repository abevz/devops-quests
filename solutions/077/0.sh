set -euo pipefail
cd ~/quest
for pod in $(kubectl get pods -l app=board -o jsonpath='{.items[*].metadata.name}'); do
 kubectl exec "$pod" -- touch /tmp/site/ready
done
kubectl wait --for=condition=Ready pod -l app=board --timeout=60s
kubectl patch pdb board-budget --type=merge -p '{"spec":{"minAvailable":1}}'
for i in $(seq 1 30); do
 if kubectl get pdb board-budget -o json | jq -e '.status.currentHealthy==2 and .status.disruptionsAllowed==1' >/dev/null; then break; fi
 sleep 1
done
pod=$(kubectl get pods -l app=board -o jsonpath='{.items[0].metadata.name}')
uid=$(kubectl get pod "$pod" -o jsonpath='{.metadata.uid}')
jq -n --arg pod "$pod" --arg ns "$DQ_NAMESPACE" --arg uid "$uid" '{apiVersion:"policy/v1",kind:"Eviction",metadata:{name:$pod,namespace:$ns},deleteOptions:{preconditions:{uid:$uid},gracePeriodSeconds:15}}' > eviction.json
kubectl create --raw "/api/v1/namespaces/$DQ_NAMESPACE/pods/$pod/eviction" -f eviction.json >/dev/null
for i in $(seq 1 60); do
 test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = north-77
 if test -z "$(kubectl get pod "$pod" --ignore-not-found -o jsonpath='{.metadata.uid}')" && kubectl get pdb board-budget -o json | jq -e '.status.currentHealthy==2 and .status.disruptionsAllowed==1' >/dev/null; then break; fi
 sleep 1
done
kubectl rollout status deployment/board --timeout=60s
