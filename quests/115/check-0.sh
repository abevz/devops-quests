set -euo pipefail
cd ~/quest
kubectl get service board -o json | jq -e '.spec.selector=={app:"green"}' >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = green-115
