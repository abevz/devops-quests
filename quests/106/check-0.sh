set -euo pipefail
cd ~/quest
kubectl get service board-internal board-headless board-node -o json | jq '[.items[] | {name:.metadata.name,uid:.metadata.uid,type:.spec.type,clusterIP:.spec.clusterIP,clusterIPs:.spec.clusterIPs,ports:.spec.ports}] | sort_by(.name)' > /tmp/dq-live-services.json
jq -e --slurpfile original /run/dq/facts/0/service-contracts.json '.==$original[0]' /tmp/dq-live-services.json >/dev/null
kubectl get service board-internal -o json | jq -e '.spec.type=="ClusterIP" and .spec.clusterIP!="None" and .spec.selector=={app:"board"}' >/dev/null
kubectl get service board-headless -o json | jq -e '.spec.clusterIP=="None" and .spec.selector=={app:"board"}' >/dev/null
kubectl get service board-node -o json | jq -e '.spec.type=="NodePort" and .spec.selector=={app:"board"} and .spec.ports[0].nodePort>=30000' >/dev/null
for name in board-internal board-headless board-node; do
 test "$(kubectl exec deployment/client -- wget -qO- -T 3 "http://$name:8080")" = north-106
done
node=$(kubectl config view --minify -o json | jq -r '.clusters[0].cluster.server | sub("^https://";"") | split(":")[0]')
port=$(kubectl get service board-node -o jsonpath='{.spec.ports[0].nodePort}')
test "$(kubectl exec deployment/client -- wget -qO- -T 3 "http://$node:$port")" = north-106
pod_ip=$(kubectl get pod -l app=board -o jsonpath='{.items[0].status.podIP}')
kubectl exec deployment/client -- nslookup -type=A "board-headless.$DQ_NAMESPACE.svc.cluster.local." | grep -F "$pod_ip" >/dev/null
