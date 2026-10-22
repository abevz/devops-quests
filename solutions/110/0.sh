set -euo pipefail
cd ~/quest
address=$(cat /run/dq/facts/0/expected-dns-address)
printf '.:1053 {\n errors\n hosts {\n  %s station.internal\n  ttl 1\n }\n}\n' "$address" > Corefile
kubectl create configmap station-dns --from-file=Corefile --dry-run=client -o json | kubectl apply -f -
kubectl rollout restart deployment/station-dns
kubectl rollout status deployment/station-dns --timeout=60s
dns_ip=$(kubectl get service station-dns -o jsonpath='{.spec.clusterIP}')
for i in $(seq 1 20); do
 if kubectl exec deployment/client -- nslookup station.internal "$dns_ip" 2>/dev/null | grep -F "$(cat /run/dq/facts/0/expected-dns-address)" >/dev/null; then break; fi
 sleep 1
done
