set -euo pipefail
cd ~/quest
test "$(kubectl get statefulset shelf -o jsonpath='{.metadata.uid}')" = "$(cat /run/dq/facts/0/original-statefulset-uid)"
test "$(kubectl get pvc ledger-shelf-0 -o jsonpath='{.metadata.uid}')" = "$(cat /run/dq/facts/0/original-pvc-uid)"
test "$(kubectl get pod shelf-0 -o jsonpath='{.metadata.uid}')" != "$(cat /run/dq/facts/0/original-pod-uid)"
kubectl get statefulset shelf -o json | jq -e '.spec.serviceName=="shelf" and .status.readyReplicas==1 and .spec.template.spec.containers[0].volumeMounts==[{name:"ledger",mountPath:"/data"}]' >/dev/null
kubectl get service shelf -o json | jq -e '.spec.clusterIP=="None" and .spec.selector=={app:"shelf"}' >/dev/null
test "$(kubectl exec shelf-0 -- wget -qO- -T 3 http://shelf-0.shelf:8080)" = ledger-111
kubectl exec shelf-0 -- nslookup -type=A "shelf-0.shelf.$DQ_NAMESPACE.svc.cluster.local." >/dev/null
