set -euo pipefail
cd ~/quest
dns_ip=$(kubectl get service station-dns -o jsonpath='{.spec.clusterIP}')
kubectl get deployment client -o json | jq -e --arg ip "$dns_ip" '.spec.template.spec.dnsPolicy=="None" and .spec.template.spec.dnsConfig.nameservers==[$ip]' >/dev/null
kubectl exec deployment/client -- nslookup station.internal "$dns_ip" | grep -F "$(cat /run/dq/facts/0/expected-dns-address)" >/dev/null
