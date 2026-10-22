set -euo pipefail
cd ~/quest
kubectl get pdb board-budget -o json | jq -e '.spec.minAvailable==1 and .spec.selector.matchLabels=={app:"board"} and .status.currentHealthy==2 and .status.desiredHealthy==1 and .status.disruptionsAllowed==1' >/dev/null
kubectl get deployment board -o json | jq -e '.spec.replicas==2 and .status.readyReplicas==2' >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = north-77
jq -e --slurpfile original /run/dq/facts/0/original-pod-uids.json --arg ns "$DQ_NAMESPACE" '.apiVersion=="policy/v1" and .kind=="Eviction" and .metadata.namespace==$ns and (.deleteOptions.preconditions.uid as $u | $original[0]|index($u)!=null)' eviction.json >/dev/null
kubectl get pods -l app=board -o json | jq -e --slurpfile original /run/dq/facts/0/original-pod-uids.json --arg uid "$(jq -er .deleteOptions.preconditions.uid eviction.json)" '([.items[].metadata.uid]|index($uid))==null and ([.items[].metadata.uid as $u|select($original[0]|index($u)!=null)]|length)==1' >/dev/null
jq -e --arg uid "$(jq -er .deleteOptions.preconditions.uid eviction.json)" 'index($uid)!=null' /run/dq/observations/evictions.json >/dev/null
test "$(kubectl auth can-i patch pods --subresource=status)" = no
