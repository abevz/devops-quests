set -euo pipefail
cd ~/quest
kubectl get role station-reader -o json | jq -e '.rules==[{apiGroups:[""],resources:["configmaps"],resourceNames:["route"],verbs:["get"]}]' >/dev/null
kubectl get rolebinding station-reader -o json | jq -e --arg ns "$DQ_NAMESPACE" '.subjects==[{kind:"ServiceAccount",name:"controller",namespace:$ns}]' >/dev/null
api=$(cat /run/dq/facts/0/api-endpoint)
controller=$(kubectl exec deployment/controller -- cat /credential/token)
observer=$(kubectl exec deployment/observer -- cat /credential/token)
test "$(curl --cacert /run/dq/facts/0/api-ca.pem -sS -o /tmp/allowed-route -w '%{http_code}' -H "Authorization: Bearer $controller" "$api/api/v1/namespaces/$DQ_NAMESPACE/configmaps/route")" = 200
jq -e '.data.route=="north-125"' /tmp/allowed-route >/dev/null
for path in configmaps configmaps/offlimits secrets secrets/control; do
 test "$(curl --cacert /run/dq/facts/0/api-ca.pem -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $controller" "$api/api/v1/namespaces/$DQ_NAMESPACE/$path")" = 403
done
test "$(curl --cacert /run/dq/facts/0/api-ca.pem -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $observer" "$api/api/v1/namespaces/$DQ_NAMESPACE/configmaps/route")" = 403
unset controller observer
