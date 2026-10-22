set -euo pipefail
cd ~/quest
uid=$(kubectl get stationboard station -o jsonpath='{.metadata.uid}')
for resource in deployment/board configmap/board-route service/board; do
 kubectl get "$resource" -o json | jq -e --arg uid "$uid" 'any(.metadata.ownerReferences[]?;.apiVersion=="training.devops-quests.local/v1" and .kind=="StationBoard" and .name=="station" and .uid==$uid and .controller==true)' >/dev/null
done
kubectl get stationboard station -o json | jq -e '.spec.route=="north-116" and .status.observedGeneration==.metadata.generation and .status.ready==true' >/dev/null
kubectl get deployment board -o json | jq -e '.metadata.labels["devops-quests.controller"]=="station-board" and .status.readyReplicas==1' >/dev/null
kubectl get configmap board-route -o json | jq -e '.data["index.html"]=="north-116\n"' >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = north-116
