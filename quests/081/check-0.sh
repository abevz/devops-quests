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

import subprocess

from dq_check import tofu_json

matched = file_resources(resource_records(tofu_json("show", "-json")), 'release.txt', in_module=False)
if not matched:
    print("Managed producer file is missing: ✗ [DQ:state]")
    sys.exit(1)
DQ_PROPERTY
python3 -I - <<'DQ_DELIVERY_PRODUCER'
import json,os,subprocess,sys,tempfile
from pathlib import Path
from dq_check import resource_records,file_resources,tofu_json

def expected(release,identity):
    return {'release':release,'producer_id':identity,'targets':{host:{'target':host,'release':release,'producer_id':identity} for host in ['app1','app2','app3']}}
def current():
    identity=json.loads(Path('/run/dq/facts/0/producer-identity.json').read_text())
    assert isinstance(identity,str) and identity
    document=tofu_json('show','-json');records=resource_records(document)
    producers=[r for _,r in records if r.get('mode')=='managed' and r.get('address')=='terraform_data.producer']
    assert len(producers)==1 and producers[0]['values']['id']==identity
    files=file_resources(records,'release.txt',in_module=False)
    assert len(files)==1 and files[0][1]['values']['content'].strip()=='release-81'
    contract=tofu_json('output','-json','delivery');assert contract==expected('release-81',identity)
    return contract

def receipts(contract):
    suffix=os.environ['DQ_NAMESPACE'].removeprefix('dq-')
    for host,entry in contract['targets'].items():
        result=subprocess.run(['ssh','-n','-o','BatchMode=yes','-o','ConnectTimeout=3','-p','2222','root@'+host+'-'+suffix,'cat /srv/site/delivery.json; printf "\\n"; stat -c %a /srv/site/delivery.json'],capture_output=True,text=True,timeout=5)
        assert result.returncode==0
        content,mode=result.stdout.rstrip('\n').rsplit('\n',1)
        assert mode=='644' and json.loads(content)==entry

try:
    contract=current()
    identity=contract['producer_id']
    schema=json.loads(Path('/run/dq/facts/0/delivery-schema.json').read_text())
    for release in schema['input_cases']:
        with tempfile.TemporaryDirectory(prefix='dq-delivery-') as directory:
            saved=str(Path(directory)/'input.plan')
            subprocess.run(['tofu','plan','-input=false','-no-color','-var','release='+release,'-out='+saved],check=True,capture_output=True,timeout=30)
            plan=tofu_json('show','-json',saved)
            assert plan['planned_values']['outputs']['delivery']['value']==expected(release,identity)
            records=resource_records(plan,'planned_values')
            files=file_resources(records,'release.txt',in_module=False)
            assert len(files)==1 and files[0][1]['values']['content'].strip()==release
            identities=[r for _,r in records if r.get('address')=='terraform_data.producer']
            assert len(identities)==1 and identities[0]['values']['id']==identity
except (AssertionError,KeyError,ValueError,TypeError,AttributeError,OSError,subprocess.SubprocessError):
    print('The delivery contract must follow caller input and retain the recorded producer identity: ✗ [DQ:delivery_producer]')
    sys.exit(1)
DQ_DELIVERY_PRODUCER
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
failed=0
if ! test "$(cat release.txt 2>/dev/null)" = release-81; then
  printf '%s\n' 'release.txt = release-81: ✗ [DQ:file]'; failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan exits 0: ✗ [DQ:plan]'; failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
