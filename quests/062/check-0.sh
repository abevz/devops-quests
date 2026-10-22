set -euo pipefail
cd ~/quest
kubectl get networkpolicy board-ingress -o json | jq -e '.spec=={podSelector:{matchLabels:{app:"board"}},policyTypes:["Ingress"],ingress:[{from:[{podSelector:{matchLabels:{role:"dispatcher"}}}],ports:[{protocol:"TCP",port:8080}]}]}' >/dev/null
test "$(kubectl get networkpolicy -o json | jq '.items|length')" = 1
test "$(kubectl exec deployment/dispatcher -- wget -qO- -T 3 http://board:8080)" = north-62
if kubectl exec deployment/visitor -- wget -qO- -T 2 http://board:8080 >/dev/null 2>&1; then exit 1; fi
