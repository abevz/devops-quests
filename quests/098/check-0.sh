set -euo pipefail
cd ~/quest
test "$(tofu output -raw managed_id)" = "$(cat /run/dq/facts/0/original-id)"
test "$(cat managed-route.txt)" = north-98
tofu output -json contract | jq -e '.=={route:"north-98"}' >/dev/null
jq -e '.=={route:"north-98"}' contract.json >/dev/null
tofu plan -input=false -detailed-exitcode -no-color -out=/tmp/verify-contract.plan >/dev/null
tofu show -json /tmp/verify-contract.plan | jq -e '.configuration.root_module.module_calls.station.module.outputs.route.expression.references | index("local_file.contract.content") != null' >/dev/null
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/message)" = north-98; test "$(stat -c %a /srv/site/message)" = 644'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/message)" = north-98; test "$(stat -c %a /srv/site/message)" = 644'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/message)" = north-98; test "$(stat -c %a /srv/site/message)" = 644'
for n in 1 2 3; do test "$(curl -fsS "http://app$n-${DQ_NAMESPACE#dq-}:8080")" = north-98; done
kubectl get configmap route -o json | jq -e '.data=={route:"north-98"}' >/dev/null
kubectl get deployment board -o json | jq -e '.spec.replicas==1 and .spec.template.spec.containers[0].env==[{name:"ROUTE",valueFrom:{configMapKeyRef:{name:"route",key:"route"}}}]' >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-98
