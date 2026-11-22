set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set +e
(
set -e
kubectl get role route-reader -o json | jq -e 'def exact($items): type=="array" and unique==$items; .rules | type=="array" and length>0 and all(.[]; (.apiGroups|exact([""])) and (.resources|exact(["configmaps"])) and (.resourceNames|exact(["route"])) and (.verbs|exact(["get"])) and ((.nonResourceURLs//[])|length==0))' >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The route-reader Role contract could not be verified: ✗ [DQ:role_contract]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
pod=$(kubectl get pods -l app=identity -o jsonpath='{.items[0].metadata.name}')
token=$(kubectl exec "$pod" -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
test "$(kubectl --token="$token" get configmap route -o jsonpath='{.data.route}')" = north
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The workload route read could not be verified: ✗ [DQ:route_read]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
pod=$(kubectl get pods -l app=identity -o jsonpath='{.items[0].metadata.name}')
token=$(kubectl exec "$pod" -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
if kubectl --token="$token" get configmap restricted >/dev/null 2>&1; then exit 1; fi
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The restricted ConfigMap denial could not be verified: ✗ [DQ:restricted_denied]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
pod=$(kubectl get pods -l app=identity -o jsonpath='{.items[0].metadata.name}')
token=$(kubectl exec "$pod" -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
if kubectl --token="$token" get secrets >/dev/null 2>&1; then exit 1; fi
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The Secrets listing denial could not be verified: ✗ [DQ:secrets_denied]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
