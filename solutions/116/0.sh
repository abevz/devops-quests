set -euo pipefail
cd ~/quest
kubectl patch stationboard station --type=json -p '[{"op": "replace", "path": "/spec/route", "value": "north-116"}]'
for i in $(seq 1 90); do
 if kubectl get stationboard station -o json | jq -e '.status.observedGeneration==.metadata.generation and .status.ready==true' >/dev/null && test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = north-116; then break; fi
 sleep 1
done
