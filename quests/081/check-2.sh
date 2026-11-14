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
failed=0
if ! kubectl rollout status deployment/relay --timeout=3s >/dev/null 2>&1; then
  printf '%s\n' 'deployment/relay rollout complete: ✗ [DQ:rollout]'; failed=1
fi
test "$failed" -eq 0
python3 -I - <<'DQ_DELIVERY_RELAY'
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
    receipts(contract)
    subprocess.run(['tofu','plan','-input=false','-detailed-exitcode','-no-color'],capture_output=True,check=True,timeout=30)
    value=subprocess.run(['kubectl','exec','--pod-running-timeout=5s','deployment/relay','-c','worker','--','printenv','DELIVERY_CONTRACT'],capture_output=True,text=True,check=True,timeout=10)
    assert json.loads(value.stdout)==contract
except (AssertionError,KeyError,ValueError,TypeError,AttributeError,OSError,subprocess.SubprocessError):
    print('The running relay must carry the current producer contract and the fleet must retain the same delivery: ✗ [DQ:delivery_relay]')
    sys.exit(1)
DQ_DELIVERY_RELAY
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_2_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/relay -c worker -- printenv RELEASE 2>/dev/null)" = release-81; then
  printf '%s\n' 'deployment/relay RELEASE = release-81: ✗ [DQ:relay]'; failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
