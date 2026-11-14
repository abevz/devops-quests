set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu validate -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
sha256sum -c /run/dq/facts/0/original-module.sha256 >/dev/null
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

records = resource_records(tofu_json('show', '-json'))
north = file_resources(records, 'north.txt', in_module=True)
south = file_resources(records, 'south.txt', in_module=True)
east = file_resources(records, 'east.txt', in_module=True)
archive = file_resources(records, 'archive.txt', in_module=True)
groups=[north,south,east,archive]
valid = len(records) == 4 and all(len(group)==1 for group in groups) and len({group[0][0] for group in groups if group})==4
sys.exit(0 if valid else 1)
DQ_PROPERTY
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
test "$(cat north.txt)" = dispatch:north
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat south.txt)" = dispatch:north:south
if ! test "$(cat east.txt)" = dispatch:east || ! test "$(cat archive.txt)" = 'dispatch:north:south|dispatch:east:archive'; then
 printf '%s\n' 'Construct the independent branch and joined delivery described by the route contract: ✗ [DQ:dag_delivery]'
 exit 1
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
tofu output -json routes | jq -e '.=={north:"dispatch:north",south:"dispatch:north:south"}' >/dev/null
python3 -I - <<'DQ_DAG_CONTRACT'
import json,re,subprocess,sys,tempfile
from pathlib import Path
from dq_check import resource_records,file_resources,tofu_json
def dependency_edges(source):
    tokens = []
    position = 0
    while position < len(source):
        character = source[position]
        if character.isspace():
            position += 1
        elif source.startswith('//', position) or character == '#':
            end = source.find('\n', position)
            position = len(source) if end < 0 else end
        elif source.startswith('/*', position):
            end = source.find('*/', position + 2)
            if end < 0:
                return {}
            position = end + 2
        elif character == '"':
            start = position
            position += 1
            while position < len(source):
                if source[position] == '\\':
                    position += 2
                elif source[position] == '"':
                    position += 1
                    break
                else:
                    position += 1
            try:
                name = json.loads(source[start:position])
            except ValueError:
                return {}
            if name.startswith('[root] '):
                name = name[len('[root] '):]
            name = re.sub(r' \(expand\)$', '', name)
            tokens.append(('node', name))
        elif source.startswith('->', position):
            tokens.append(('arrow', '->'))
            position += 2
        else:
            # Preserve barriers; attribute labels cannot become graph edges.
            tokens.append(('other', character))
            position += 1
    edges = {}
    for left, arrow, right in zip(tokens, tokens[1:], tokens[2:]):
        if left[0] == right[0] == 'node' and arrow[0] == 'arrow':
            edges.setdefault(left[1], set()).add(right[1])
    return edges


def ordered_after(edges, later, earlier):
    pending = [later]
    seen = set()
    while pending:
        node = pending.pop()
        if node in seen:
            continue
        seen.add(node)
        for dependency in edges.get(node, ()):
            if dependency == earlier:
                return True
            pending.append(dependency)
    return False

try:
    contract=json.loads(Path('/run/dq/facts/0/route-cases.json').read_text())
    records=resource_records(tofu_json('show','-json'))
    addresses={}
    for filename in contract['cases'][0]['files']:
        found=file_resources(records,filename,in_module=True);assert len(found)==1
        addresses[filename]=re.sub(r'\[[^]]+\]','',found[0][1]['address'])
    graph=subprocess.run(['tofu','graph'],capture_output=True,text=True,timeout=20,check=True)
    edges=dependency_edges(graph.stdout)
    for later,earlier in contract['dependencies'].items():
        assert all(ordered_after(edges,addresses[later],addresses[item]) for item in earlier)
except (AssertionError,KeyError,TypeError,ValueError,AttributeError,OSError,subprocess.SubprocessError):
    print('The joined delivery must have real resource dependencies on both upstream branches: ✗ [DQ:dag_dependencies]')
    sys.exit(1)
try:
    with tempfile.TemporaryDirectory() as directory:
        for case in contract['cases']:
            plan=Path(directory)/'routes.tfplan'
            subprocess.run(['tofu','plan','-input=false','-refresh=false','-no-color','-out='+str(plan),'-var='+contract['variable']+'='+case['input']],capture_output=True,text=True,timeout=30,check=True)
            document=tofu_json('show','-json',str(plan));rows=resource_records(document,'planned_values')
            for filename,wanted in case['files'].items():
                found=file_resources(rows,filename,in_module=True);assert len(found)==1 and found[0][1]['values']['content'].rstrip('\n')==wanted
            outputs=document['planned_values']['outputs']
            assert outputs['routes']['value']=={'north':case['files']['north.txt'],'south':case['files']['south.txt']}
            assert outputs['delivery_routes']['value']=={'east':case['files']['east.txt'],'archive':case['files']['archive.txt']}
    delivery=tofu_json('output','-json','delivery_routes')
    assert delivery=={'east':'dispatch:east','archive':'dispatch:north:south|dispatch:east:archive'}
except (AssertionError,KeyError,TypeError,ValueError,AttributeError,OSError,subprocess.SubprocessError):
    print('The complete route graph must forward every supplied caller value through its real managed files and delivery outputs: ✗ [DQ:dag_contract]')
    sys.exit(1)
DQ_DAG_CONTRACT
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
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
