set -euo pipefail
cd ~/quest
kubectl get deployment reader -o json | jq -e '.spec.template.spec.automountServiceAccountToken==false and .spec.template.spec.volumes[0].projected.sources[0].serviceAccountToken=={path:"token",expirationSeconds:600,audience:"https://kubernetes.default.svc.cluster.local"}' >/dev/null
token=$(kubectl exec deployment/reader -- cat /credential/token)
api=$(cat /run/dq/facts/0/api-endpoint)
status=$(curl --cacert /run/dq/facts/0/api-ca.pem -sS -o /tmp/route-result -w '%{http_code}' -H "Authorization: Bearer $token" "$api/api/v1/namespaces/$DQ_NAMESPACE/configmaps/route")
test "$status" = 200
jq -e '.data.route=="north-114"' /tmp/route-result >/dev/null
for resource in configmaps secrets; do
 test "$(curl --cacert /run/dq/facts/0/api-ca.pem -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" "$api/api/v1/namespaces/$DQ_NAMESPACE/$resource")" = 403
done
unset token
test "$(curl --cacert /run/dq/facts/0/api-ca.pem -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $(kubectl exec deployment/reader -- cat /credential/token)" "$api/api/v1/namespaces/$DQ_NAMESPACE/configmaps/offlimits")" = 403
kubectl get role reader -o json | jq -e '.rules==[{apiGroups:[""],resources:["configmaps"],resourceNames:["route"],verbs:["get"]}]' >/dev/null
