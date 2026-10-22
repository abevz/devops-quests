set -euo pipefail
cd ~/quest
kubectl get networkpolicy client-egress -o json | jq -e '.spec.podSelector=={matchLabels:{app:"client"}} and .spec.policyTypes==["Egress"] and (.spec.egress|length)==2' >/dev/null
kubectl exec deployment/client -- nslookup -type=A "board.$DQ_NAMESPACE.svc.cluster.local." >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = north-119
closed=$(kubectl get service closed -o jsonpath='{.spec.clusterIP}')
if kubectl exec deployment/client -- wget -qO- -T 2 "http://$closed:8080" >/dev/null 2>&1; then exit 1; fi
kubectl get networkpolicy client-egress -o json | jq -e '.spec=={"podSelector": {"matchLabels": {"app": "client"}}, "policyTypes": ["Egress"], "egress": [{"to": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "kube-system"}}, "podSelector": {"matchLabels": {"k8s-app": "kube-dns"}}}], "ports": [{"port": 53, "protocol": "UDP"}, {"port": 53, "protocol": "TCP"}]}, {"to": [{"podSelector": {"matchLabels": {"app": "board"}}}], "ports": [{"port": 8080, "protocol": "TCP"}]}]}' >/dev/null
