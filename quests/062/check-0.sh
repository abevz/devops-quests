set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
kubectl get networkpolicy board-ingress -o json | jq -e '.spec=={podSelector:{matchLabels:{app:"board"}},policyTypes:["Ingress"],ingress:[{from:[{podSelector:{matchLabels:{role:"dispatcher"}}}],ports:[{protocol:"TCP",port:8080}]}]}' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl get networkpolicy -o json | jq '.items|length')" = 1
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/dispatcher -- wget -qO- -T 3 http://board:8080)" = north-62
)
[ $? -eq 0 ] || failed=1
(
set -e
if kubectl exec deployment/visitor -- wget -qO- -T 2 http://board:8080 >/dev/null 2>&1; then exit 1; fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
