set -euo pipefail
cd ~/quest
test "$(kubectl get pvc ledger-shelf-0 -o jsonpath='{.metadata.uid}')" = "$(cat /run/dq/facts/0/original-pvc-uid)"
kubectl get service shelf -o json | jq -e '.spec.clusterIP=="None" and .spec.selector=={app:"shelf"}' >/dev/null
kubectl exec deployment/client -- nslookup -type=A "shelf-0.shelf.$DQ_NAMESPACE.svc.cluster.local." >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://shelf-0.shelf:8080)" = ledger-120
kubectl get networkpolicy client-egress -o json | jq -e '.spec.policyTypes==["Egress"] and (.spec.egress|length)==2' >/dev/null
kubectl get networkpolicy client-egress -o json | jq -e '.spec=={"podSelector": {"matchLabels": {"app": "client"}}, "policyTypes": ["Egress"], "egress": [{"to": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "kube-system"}}, "podSelector": {"matchLabels": {"k8s-app": "kube-dns"}}}], "ports": [{"port": 53, "protocol": "UDP"}, {"port": 53, "protocol": "TCP"}]}, {"to": [{"podSelector": {"matchLabels": {"app": "shelf"}}}], "ports": [{"port": 8080, "protocol": "TCP"}]}]}' >/dev/null
