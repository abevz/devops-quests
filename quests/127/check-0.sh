set -euo pipefail
cd ~/quest
kubectl get service board -o json | jq -e '.spec.ports[0].port==8080 and .spec.ports[0].targetPort==8080 and .spec.selector=={app:"board"}' >/dev/null
url=$(jq -r .url /run/dq/facts/0/prometheus-target.json)
kubectl exec deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=up%7Bjob%3D%22board%22%7D" | jq -e '.status=="success" and (.data.result|length)==1 and .data.result[0].value[1]=="1"' >/dev/null
kubectl exec deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=sum%28station_queue_depth%7Bjob%3D%22board%22%2Croute%3D%22north%22%7D%29" | jq -e '.status=="success" and (.data.result|length)==1 and .data.result[0].value[1]=="7"' >/dev/null
kubectl exec deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=count%28station_queue_depth%7Bjob%3D%22board%22%2Croute%3D%22north%22%7D%29" | jq -e '.status=="success" and (.data.result|length)==1 and .data.result[0].value[1]=="2"' >/dev/null
kubectl exec deployment/client -- wget -qO- -T 3 "$url/api/v1/targets?state=active" | jq -e 'any(.data.activeTargets[]?;.labels.job=="board" and .health=="up" and .lastError=="")' >/dev/null
