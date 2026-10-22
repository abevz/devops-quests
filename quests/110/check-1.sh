set -euo pipefail
cd ~/quest
dns_ip=$(kubectl get service station-dns -o jsonpath='{.spec.clusterIP}')
kubectl get deployment client -o json | jq -e --arg ip "$dns_ip" '.spec.template.spec.dnsPolicy=="None" and .spec.template.spec.dnsConfig.nameservers==[$ip]' >/dev/null
kubectl exec deployment/client -- nslookup station.internal "$dns_ip" | grep -F "$(cat /run/dq/facts/0/expected-dns-address)" >/dev/null
url=http://station.internal:8000
class=$(jq -er .class /run/dq/facts/0/ingress-target.json)
kubectl get ingress board -o json | jq -e --arg class "$class" --arg host station.internal '.spec.ingressClassName==$class and .spec.rules[0].host==$host and .spec.rules[0].http.paths[0].path=="/" and .spec.rules[0].http.paths[0].pathType=="Prefix" and .spec.rules[0].http.paths[0].backend.service=={name:"board",port:{number:8080}}' >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 --header='Host: station.internal' "$url")" = north-110
if kubectl exec deployment/client -- wget -qO- -T 3 --header='Host: wrong.station.internal' "$url" >/dev/null 2>&1; then exit 1; fi
