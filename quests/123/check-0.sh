set -euo pipefail
cd ~/quest
ns=$(jq -r .namespace /run/dq/facts/0/appset-target.json)
kubectl -n "$ns" get applicationset station -o json | jq -e '.spec.template.spec.source.path=="stations/{{.station}}" and .spec.goTemplate==true and (.spec.generators[0].list.elements|map(.station))==["north","south"]' >/dev/null
bash wait-apps.sh
for station in north south; do
 kubectl get deployment "$station" -o json | jq -e '.status.readyReplicas==1' >/dev/null
 test "$(kubectl exec deployment/"$station" -- wget -qO- -T 3 http://"$station":8080)" = "$station-123"
done
