set -euo pipefail
cd ~/quest
jq '.spec.limits[0].default.cpu="200m" | .spec.limits[0].defaultRequest.cpu="100m"' defaults.json > /tmp/fixed-defaults.json
cp /tmp/fixed-defaults.json defaults.json
kubectl apply -f defaults.json
# With the client and one board Pod, the quota has no room for a surge Pod.
kubectl scale deployment/board --replicas=0
settled=false
for attempt in $(seq 1 60); do
  pods=$(kubectl get pods -l app=board -o json)
  replicasets=$(kubectl get replicasets -l app=board -o json)
  if jq -e '.items | length==0' <<<"$pods" >/dev/null && jq -e 'all(.items[]; .spec.replicas==0)' <<<"$replicasets" >/dev/null; then
    settled=true
    break
  fi
  sleep 1
done
if ! "$settled"; then printf '%s\n' 'board Pods or ReplicaSets did not scale down within 60 seconds' >&2; exit 1; fi
kubectl rollout restart deployment/board
kubectl scale deployment/board --replicas=1
kubectl rollout status deployment/board --timeout=90s
