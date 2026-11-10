set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
failed=0
original=$(cat /run/dq/facts/0/original-id 2>/dev/null || true)
actual=$(tofu output -raw managed_id 2>/dev/null || true)
if ! test -n "$original" || ! test "$actual" = "$original"; then printf '%s\n' 'managed_id = original-id: ✗ [DQ:managed_id]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
dq_property_failed=0
set +e
(
set -e
dq_property_failed=0
set +e
(
set -e
failed=0
if ! test "$(cat managed-route.txt 2>/dev/null)" = north-98; then printf '%s\n' 'managed-route.txt = north-98: ✗ [DQ:route_file]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || dq_property_failed=1
(
set -e
failed=0
require() { local message=$1; shift; if ! "$@" >/dev/null 2>&1; then printf '%s\n' "$message: ✗"; failed=1; fi; }
check_jq() { jq -e "$1" <<<"$2"; }
contract=$(tofu output -json contract 2>/dev/null || true)
require 'tofu output contract route = north-98 [DQ:contract_output]' check_jq '.route=="north-98"' "$contract"
require 'contract.json route = north-98 [DQ:contract_file]' jq -e '.route=="north-98"' contract.json
exit "$failed"
)
[ $? -eq 0 ] || dq_property_failed=1
(
set -e
failed=0
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  if ! test "$(curl -fsS --max-time 3 "http://$host:8080" 2>/dev/null)" = north-98; then printf '%s\n' "$host:8080 = north-98: ✗ [DQ:http_$n]"; failed=1; fi
done
exit "$failed"
)
[ $? -eq 0 ] || dq_property_failed=1
(
set -e
failed=0
require() { local message=$1; shift; if ! "$@" >/dev/null 2>&1; then printf '%s\n' "$message: ✗"; failed=1; fi; }
check_jq() { jq -e "$1" <<<"$2"; }
route=$(kubectl get configmap route -o json 2>/dev/null || true)
require 'configmap/route route = north-98 [DQ:configmap]' check_jq '.data.route=="north-98"' "$route"
exit "$failed"
)
[ $? -eq 0 ] || dq_property_failed=1
(
set -e
failed=0
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-98; then printf '%s\n' 'board:8080 = north-98: ✗ [DQ:board_http]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || dq_property_failed=1
set -e
test "$dq_property_failed" -eq 0
)
[ $? -eq 0 ] || dq_property_failed=1
(
set -e
failed=0
python3 -I - <<'DQ_REFERENCE'
import json
import os
import stat
import sys
from pathlib import Path


from dq_check import read_json


from dq_check import resource_records


from dq_check import same_target


from dq_check import file_resources


from dq_check import number_is

import json
import re
from pathlib import Path
















from dq_check import module_forwards as _dq_forwards

def module_forwards(directory, references, endpoint, output_name='route'):
    return _dq_forwards(directory, references, endpoint, output_name, dialect='output')

import subprocess
import tempfile

def verify_forwarding():
    with tempfile.NamedTemporaryFile() as saved:
        result = subprocess.run(['tofu', 'plan', '-input=false', '-detailed-exitcode', '-no-color', '-out=' + saved.name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode not in (0, 2):
            return False
        result = subprocess.run(['tofu', 'show', '-json', saved.name], capture_output=True, text=True)
        if result.returncode != 0:
            return False
        try:
            plan = json.loads(result.stdout)
            call = plan['configuration']['root_module']['module_calls']['station']
            refs = call['module']['outputs']['route']['expression']['references']
            source = call['source']
        except (ValueError, KeyError, TypeError):
            return False
        # Read the current local module source, not an outdated cached module copy.
        if not isinstance(source, str) or not source.startswith(('./', '../', '/')):
            return False
        producers = file_resources(resource_records(plan, 'planned_values'), 'managed-route.txt', in_module=True)
        for module, resource in producers:
            if module != 'module.station':
                continue
            address = resource.get('address', '')
            prefix = 'module.station.'
            if not address.startswith(prefix):
                continue
            endpoint = address[len(prefix):] + '.content'
            if module_forwards(source, refs, endpoint):
                return True
        return False

if not verify_forwarding():
    print('The module output must forward the managed producer file contents: ✗ [DQ:reference]')
    sys.exit(1)
DQ_REFERENCE
)
[ $? -eq 0 ] || dq_property_failed=1
set -e
test "$dq_property_failed" -eq 0
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_1]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  result=$(timeout 4s ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'actual=$(sha256sum /srv/site/message 2>/dev/null | cut -d " " -f 1); if test "$actual" = bdbf510116b9f7963361e3e7b5f3621586fc01e42d2dc0aac1b97a229b1160fc || test "$actual" = 9348964429c827929d2d5467b62a30c15c416b43714c5c8a6471d60804d2cfbf; then printf "content-ok\n"; fi; if test "$(stat -c %a /srv/site/message 2>/dev/null)" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
  if ! grep -Fxq content-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message = north-98: ✗ [DQ:content_$n]"; failed=1; fi
  if ! grep -Fxq mode-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message mode = 644: ✗ [DQ:mode_$n]"; failed=1; fi
done
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
plan=$(mktemp)
trap 'rm -f "$plan"' EXIT
if ! tofu plan -input=false -detailed-exitcode -no-color -out="$plan" >/dev/null 2>&1; then printf '%s\n' 'tofu plan exits 0: ✗ [DQ:plan]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
require() { local message=$1; shift; if ! "$@" >/dev/null 2>&1; then printf '%s\n' "$message: ✗"; failed=1; fi; }
check_jq() { jq -e "$1" <<<"$2"; }
board=$(kubectl get deployment board -o json 2>/dev/null || true)
require 'deployment/board replicas = 1 [DQ:replicas]' check_jq '.spec.replicas==1' "$board"
if ! check_jq '[.spec.template.spec.containers[] | select(.name=="worker")] | length==1 and (.[0].env | [.[] | select(.name=="ROUTE")] | length==1 and (.[0] | ((has("value")|not) or .value=="") and .valueFrom.configMapKeyRef.name=="route" and .valueFrom.configMapKeyRef.key=="route"))' "$board" >/dev/null 2>&1 || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- printenv ROUTE 2>/dev/null)" = north-98; then
  printf '%s\n' 'The running worker must receive north-98 from the supplied configuration without an embedded value: ✗ [DQ:board_env]'; failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
