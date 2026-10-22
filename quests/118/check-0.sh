set -euo pipefail
cd ~/quest
jq -e '.fault=="selector"' diagnosis.json >/dev/null
kubectl get service board -o json | jq -e '.spec.selector=={app:"board"}' >/dev/null
kubectl get endpointslices -l kubernetes.io/service-name=board -o json | jq -e 'any(.items[].endpoints[]?;.conditions.ready==true)' >/dev/null
ip=$(kubectl get pod -l app=board -o jsonpath='{.items[0].status.podIP}')
test "$(kubectl exec deployment/client -- wget -qO- -T 3 "http://$ip:8080")" = north-118
vip=$(kubectl get service board -o jsonpath='{.spec.clusterIP}')
test "$(kubectl exec deployment/client -- wget -qO- -T 3 "http://$vip:8080")" = north-118
jq -e '.ready==true and (.mode=="iptables" or .mode=="nftables" or .mode=="ipvs")' /run/dq/facts/0/proxy-observation.json >/dev/null
