set -euo pipefail
cd ~/quest
failed=0
require() { local message=$1; shift; if ! "$@" >/dev/null 2>&1; then printf '%s\n' "$message: ✗"; failed=1; fi; }
check_jq() { jq -e "$1" <<<"$2"; }
original=$(cat /run/dq/facts/0/original-id 2>/dev/null || true)
actual=$(tofu output -raw managed_id 2>/dev/null || true)
if ! test -n "$original" || ! test "$actual" = "$original"; then printf '%s\n' 'managed_id = original-id: ✗'; failed=1; fi
if ! test "$(cat managed-route.txt 2>/dev/null)" = north-98; then printf '%s\n' 'managed-route.txt = north-98: ✗'; failed=1; fi
contract=$(tofu output -json contract 2>/dev/null || true)
require 'tofu output contract = {route:north-98}' check_jq '.=={route:"north-98"}' "$contract"
require 'contract.json = {route:north-98}' jq -e '.=={route:"north-98"}' contract.json
plan=$(mktemp)
trap 'rm -f "$plan"' EXIT
if ! tofu plan -input=false -detailed-exitcode -no-color -out="$plan" >/dev/null 2>&1; then printf '%s\n' 'tofu plan exits 0: ✗'; failed=1; fi
if ! tofu show -json "$plan" 2>/dev/null | jq -e '.configuration.root_module.module_calls.station.module.outputs.route.expression.references | index("local_file.contract.content") != null' >/dev/null 2>&1; then printf '%s\n' 'module route references local_file.contract.content: ✗'; failed=1; fi
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  result=$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'value=$(cat /srv/site/message 2>/dev/null || true); mode=$(stat -c %a /srv/site/message 2>/dev/null || true); printf "%s\n%s\n" "$value" "$mode"' 2>/dev/null || true)
  if ! test "$(printf '%s\n' "$result" | sed -n '1p')" = north-98; then printf '%s\n' "$host /srv/site/message = north-98: ✗"; failed=1; fi
  if ! test "$(printf '%s\n' "$result" | sed -n '2p')" = 644; then printf '%s\n' "$host /srv/site/message mode = 644: ✗"; failed=1; fi
  if ! test "$(curl -fsS --max-time 3 "http://$host:8080" 2>/dev/null)" = north-98; then printf '%s\n' "$host:8080 = north-98: ✗"; failed=1; fi
done
route=$(kubectl get configmap route -o json 2>/dev/null || true)
require 'configmap/route data = {route:north-98}' check_jq '.data=={route:"north-98"}' "$route"
board=$(kubectl get deployment board -o json 2>/dev/null || true)
require 'deployment/board replicas = 1' check_jq '.spec.replicas==1' "$board"
require 'deployment/board first container env = ROUTE from route/route only' check_jq '.spec.template.spec.containers[0].env==[{name:"ROUTE",valueFrom:{configMapKeyRef:{name:"route",key:"route"}}}]' "$board"
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-98; then printf '%s\n' 'board:8080 = north-98: ✗'; failed=1; fi
exit "$failed"
