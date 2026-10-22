set -euo pipefail
cd ~/quest
url=$(jq -er .url /run/dq/facts/0/ingress-target.json)
class=$(jq -er .class /run/dq/facts/0/ingress-target.json)
kubectl get ingress board -o json | jq -e --arg class "$class" --arg host station.internal '.spec.ingressClassName==$class and .spec.rules[0].host==$host and .spec.rules[0].http.paths[0].path=="/" and .spec.rules[0].http.paths[0].pathType=="Prefix" and .spec.rules[0].http.paths[0].backend.service=={name:"board",port:{number:8080}}' >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 --header='Host: station.internal' "$url")" = north-107
if kubectl exec deployment/client -- wget -qO- -T 3 --header='Host: wrong.station.internal' "$url" >/dev/null 2>&1; then exit 1; fi
