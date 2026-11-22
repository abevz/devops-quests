set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
python3 -I - <<'DQ_PROPERTY'
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

def originals():
    try:
        addresses = Path('original-addresses').read_text().splitlines()
    except OSError:
        return set()
    return set(addresses) if len(addresses) == 2 and all(addresses) and len(set(addresses)) == 2 else set()

import json
import re
from pathlib import Path
















from dq_check import module_forwards as _dq_forwards

def module_forwards(directory, references, endpoint, output_name='station'):
    return _dq_forwards(directory, references, endpoint, output_name, dialect='module')

addresses = originals()
plan = read_json('fanout-plan.json')
records = resource_records(plan, 'planned_values')
expected = {'depot.txt': 'north:depot', 'junction.txt': 'north:junction'}
matched = set()
for filename, content in expected.items():
    candidates = [r for _, r in file_resources(records, filename) if r.get('address') in addresses and isinstance(r['values'].get('content'), str) and r['values']['content'].rstrip('\n') == content]
    matched.update(r['address'] for r in candidates)

# The supplied shared regional input is an educational constraint. Follow
# transparent aliases without equating a copied literal with that dependency.
configuration = (plan or {}).get('configuration', {}).get('root_module', {})
calls = configuration.get('module_calls', {})
labels = set()
for address in addresses:
    match = re.match(r'^module\.([A-Za-z_][A-Za-z0-9_-]*)\[', address)
    if match:
        labels.add(match.group(1))
shared_input = bool(labels) and all(
    module_forwards('.', call.get('expressions', {}).get('region', {}).get('references', []),
                    'local.region', output_name=label)
    for label in labels
    for call in [calls.get(label, {})]
)

sys.exit(0 if addresses and matched == addresses and shared_input else 1)
DQ_PROPERTY
python3 -I - <<'DQ_FANOUT_CONTRACT'
import json,subprocess,sys,tempfile
from pathlib import Path
from dq_check import resource_records,file_resources,tofu_json
try:
    contract=json.loads(Path('/run/dq/facts/0/region-cases.json').read_text())
    identities=json.loads(Path('/run/dq/facts/0/station-identities.json').read_text())
    originals=set(Path('/run/dq/facts/0/original-addresses').read_text().splitlines())
    with tempfile.TemporaryDirectory() as directory:
        for region in contract['values']:
            plan=Path(directory)/'fanout.tfplan'
            subprocess.run(['tofu','plan','-input=false','-refresh=false','-no-color','-out='+str(plan),'-var='+contract['variable']+'='+region],capture_output=True,text=True,timeout=30,check=True)
            document=tofu_json('show','-json',str(plan));records=resource_records(document,'planned_values')
            actual=set()
            for station in contract['stations']:
                group=file_resources(records,station+'.txt',in_module=True);assert len(group)==1
                record=group[0][1];assert record['values']['content'].rstrip('\n')==region+':'+station
                actual.add(record['address'])
            assert actual==originals
            changes={r['address']:r for r in document['resource_changes']}
            assert all(changes[address]['change']['actions']==['no-op'] and changes[address]['change']['before']['id']==identity for address,identity in identities.items())
except (AssertionError,KeyError,TypeError,ValueError,AttributeError,OSError,subprocess.SubprocessError):
    print('Reconstruct the nested module contract so every supplied caller value reaches both stations without replacing their identity companions: ✗ [DQ:fanout_contract]')
    sys.exit(1)
DQ_FANOUT_CONTRACT
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
python3 -I - <<'DQ_PROPERTY'
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

def originals():
    try:
        addresses = Path('original-addresses').read_text().splitlines()
    except OSError:
        return set()
    return set(addresses) if len(addresses) == 2 and all(addresses) and len(set(addresses)) == 2 else set()

addresses = originals()
plan = read_json('fanout-plan.json')
changes = plan.get('resource_changes', []) if isinstance(plan, dict) else []
replaced = set()
valid = bool(addresses) and isinstance(changes, list)
for resource in changes if isinstance(changes, list) else []:
    actions = resource.get('change', {}).get('actions')
    if resource.get('address') in addresses:
        if resource.get('mode') != 'managed' or resource.get('type') != 'local_file' or not isinstance(actions, list) or sorted(actions) != ['create', 'delete']:
            valid = False
        replaced.add(resource.get('address'))
    elif actions not in (['no-op'], ['read']):
        valid = False
sys.exit(0 if valid and replaced == addresses else 1)
DQ_PROPERTY
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
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
python3 -I - <<'DQ_PROPERTY'
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

def originals():
    try:
        addresses = Path('original-addresses').read_text().splitlines()
    except OSError:
        return set()
    return set(addresses) if len(addresses) == 2 and all(addresses) and len(set(addresses)) == 2 else set()

import subprocess

from dq_check import tofu_json

addresses = originals()
records = resource_records(tofu_json('show', '-json'))
current = {r.get('address') for _, r in records}
sys.exit(0 if addresses and addresses <= current else 1)
DQ_PROPERTY
python3 -I - <<'DQ_FANOUT_IDENTITIES'
import json,sys
from pathlib import Path
from dq_check import resource_records,tofu_json
try:
    original=Path('/run/dq/facts/0/original-addresses').read_text()
    assert Path('original-addresses').read_text()==original
    identities=json.loads(Path('/run/dq/facts/0/station-identities.json').read_text())
    records=[(module,r) for module,r in resource_records(tofu_json('show','-json')) if r.get('mode')=='managed']
    actual={r['address']:r for _,r in records}
    assert len(records)==len(actual)==4
    assert set(actual)==set(original.splitlines())|set(identities)
    assert all(actual[address]['mode']=='managed' and actual[address]['type']=='terraform_data' and actual[address]['values']['id']==identity for address,identity in identities.items())
except (AssertionError,KeyError,TypeError,ValueError,AttributeError,OSError):
    print('Retain the frozen original file addresses and each station identity, with no unrelated managed objects: ✗ [DQ:fanout_identity]')
    sys.exit(1)
DQ_FANOUT_IDENTITIES
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_2]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
test "$(cat depot.txt)" = north:depot
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The depot route file could not be verified: ✗ [DQ:fanout_depot]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
test "$(cat junction.txt)" = north:junction
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The junction route file could not be verified: ✗ [DQ:fanout_junction]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
python3 -I - <<'DQ_PROPERTY'
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

import subprocess

from dq_check import tofu_json

routes = tofu_json('output', '-json', 'routes')
valid = (isinstance(routes, dict) and set(routes) == {'depot', 'junction'}
         and same_target(routes['depot'], 'depot.txt', existing=True)
         and same_target(routes['junction'], 'junction.txt', existing=True))
sys.exit(0 if valid else 1)
DQ_PROPERTY
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_5]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
tofu plan -detailed-exitcode -input=false -no-color >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The default regional plan did not complete without changes: ✗ [DQ:fanout_plan]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
