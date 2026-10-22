set -euo pipefail
cd ~/quest
kubectl get deployment blue green -o json | jq -e 'all(.items[]; (.metadata.name=="blue" and .spec.replicas==3 and .status.readyReplicas==3) or (.metadata.name=="green" and .spec.replicas==1 and .status.readyReplicas==1))' >/dev/null
kubectl get service board -o json | jq -e '.spec.selector=={release:"board"}' >/dev/null
kubectl get endpointslices -l kubernetes.io/service-name=board -o json | jq -e '[.items[].endpoints[] | select(.conditions.ready==true) | .targetRef.name] | unique | length==4' >/dev/null
for version in blue green; do
 for ip in $(kubectl get pods -l "app=$version" -o jsonpath='{.items[*].status.podIP}'); do
  test "$(kubectl exec deployment/client -- wget -qO- -T 3 "http://$ip:8080")" = "$version-115"
 done
done
case "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" in blue-115|green-115) ;; *) exit 1;; esac
