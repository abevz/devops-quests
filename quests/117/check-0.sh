set -euo pipefail
cd ~/quest
jq -e --arg node "$DQ_NODE_NAME" '.verified==true and .source=="file" and .node==$node' /run/dq/observations/static-pod.json >/dev/null
uid=$(jq -r .mirrorUID /run/dq/observations/static-pod.json)
hash=$(jq -r .configHash /run/dq/observations/static-pod.json)
kubectl get pod "static-board-$DQ_NODE_NAME" -o json | jq -e --arg node "$DQ_NODE_NAME" --arg uid "$uid" --arg hash "$hash" '.metadata.uid==$uid and .metadata.annotations["kubernetes.io/config.mirror"]==$hash and .spec.nodeName==$node and any(.status.containerStatuses[]?;.ready==true)' >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = north-117
