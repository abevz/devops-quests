set -euo pipefail
cd ~/quest
pod=$(kubectl get pods -l app=identity -o jsonpath='{.items[0].metadata.name}')
token=$(kubectl exec "$pod" -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
test "$(kubectl --token="$token" get configmap route -o jsonpath='{.data.route}')" = north
if kubectl --token="$token" get configmap restricted >/dev/null 2>&1; then exit 1; fi
if kubectl --token="$token" get secrets >/dev/null 2>&1; then exit 1; fi
kubectl get role route-reader -o json | jq -e '.rules==[{"apiGroups":[""],"resources":["configmaps"],"resourceNames":["route"],"verbs":["get"]}]' >/dev/null
