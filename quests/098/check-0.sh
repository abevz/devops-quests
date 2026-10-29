set -euo pipefail
cd ~/quest
failed=0
require() { local message=$1; shift; if ! "$@" >/dev/null 2>&1; then printf '%s\n' "$message: ✗"; failed=1; fi; }
check_jq() { jq -e "$1" <<<"$2"; }
original=$(cat /run/dq/facts/0/original-id 2>/dev/null || true)
actual=$(tofu output -raw managed_id 2>/dev/null || true)
if ! test -n "$original" || ! test "$actual" = "$original"; then printf '%s\n' 'managed_id = original-id: ✗ [DQ:managed_id]'; failed=1; fi
if ! test "$(cat managed-route.txt 2>/dev/null)" = north-98; then printf '%s\n' 'managed-route.txt = north-98: ✗ [DQ:route_file]'; failed=1; fi
contract=$(tofu output -json contract 2>/dev/null || true)
require 'tofu output contract = {route:north-98} [DQ:contract_output]' check_jq '.=={route:"north-98"}' "$contract"
require 'contract.json = {route:north-98} [DQ:contract_file]' jq -e '.=={route:"north-98"}' contract.json
plan=$(mktemp)
trap 'rm -f "$plan"' EXIT
if ! tofu plan -input=false -detailed-exitcode -no-color -out="$plan" >/dev/null 2>&1; then printf '%s\n' 'tofu plan exits 0: ✗ [DQ:plan]'; failed=1; fi
if ! tofu show -json "$plan" 2>/dev/null | jq -e '.configuration.root_module.module_calls.station.module.outputs.route.expression.references | index("local_file.contract.content") != null' >/dev/null 2>&1; then printf '%s\n' 'module route references local_file.contract.content: ✗ [DQ:reference]'; failed=1; fi
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  result=$(timeout 4s ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'actual=$(sha256sum /srv/site/message 2>/dev/null | cut -d " " -f 1); if test "$actual" = bdbf510116b9f7963361e3e7b5f3621586fc01e42d2dc0aac1b97a229b1160fc || test "$actual" = 9348964429c827929d2d5467b62a30c15c416b43714c5c8a6471d60804d2cfbf; then printf "content-ok\n"; fi; if test "$(stat -c %a /srv/site/message 2>/dev/null)" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
  if ! grep -Fxq content-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message = north-98: ✗ [DQ:content_$n]"; failed=1; fi
  if ! grep -Fxq mode-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message mode = 644: ✗ [DQ:mode_$n]"; failed=1; fi
  if ! test "$(curl -fsS --max-time 3 "http://$host:8080" 2>/dev/null)" = north-98; then printf '%s\n' "$host:8080 = north-98: ✗ [DQ:http_$n]"; failed=1; fi
done
route=$(kubectl get configmap route -o json 2>/dev/null || true)
require 'configmap/route data = {route:north-98} [DQ:configmap]' check_jq '.data=={route:"north-98"}' "$route"
board=$(kubectl get deployment board -o json 2>/dev/null || true)
require 'deployment/board replicas = 1 [DQ:replicas]' check_jq '.spec.replicas==1' "$board"
require 'deployment/board first container env = ROUTE from route/route only [DQ:board_env]' check_jq '.spec.template.spec.containers[0].env==[{name:"ROUTE",valueFrom:{configMapKeyRef:{name:"route",key:"route"}}}]' "$board"
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-98; then printf '%s\n' 'board:8080 = north-98: ✗ [DQ:board_http]'; failed=1; fi
exit "$failed"
