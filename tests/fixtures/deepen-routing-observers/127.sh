set -euo pipefail
cd ~/quest
kubectl patch service board --type=json -p '[{"op": "replace", "path": "/spec/ports/0/targetPort", "value": 8080}]'
url=$(jq -r .url /run/dq/facts/0/prometheus-target.json)
for i in $(seq 1 30); do
 if kubectl exec deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=up%7Bjob%3D%22board%22%7D" | jq -e '.data.result[0].value[1]=="1"' >/dev/null; then break; fi
 sleep 1
done
kubectl exec deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=up%7Bjob%3D%22board%22%7D" | jq -e '.data.result[0].value[1]=="1"' >/dev/null
