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
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  result=$(timeout 4s ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'actual=$(sha256sum /srv/site/message 2>/dev/null | cut -d " " -f 1); if test "$actual" = 679654d8c0b2d19d0c05fa59f6830658bb6dcbf0e0872a66360ad0b032813982 || test "$actual" = facfe2047ac974e0f4348307cc1a8a543df489b6c451b5fbb3de2d546a89f0cb; then printf "content-ok\n"; fi; if test "$(stat -c %a /srv/site/message 2>/dev/null)" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
  if ! grep -Fxq content-ok <<<"$result"; then
    printf '%s\n' "$host /srv/site/message = release-81: ✗ [DQ:content_$n]"; failed=1
  fi
  if ! grep -Fxq mode-ok <<<"$result"; then
    printf '%s\n' "$host /srv/site/message mode = 644: ✗ [DQ:mode_$n]"; failed=1
  fi
done
test "$failed" -eq 0
python3 -I - <<'DQ_DELIVERY_FLEET'
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
except (AssertionError,KeyError,ValueError,TypeError,AttributeError,OSError,subprocess.SubprocessError):
    print('Every target receipt must contain its current producer contract with mode 0644: ✗ [DQ:delivery_fleet]')
    sys.exit(1)
DQ_DELIVERY_FLEET
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_0]'
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
  if ! test "$(curl -fsS --max-time 3 "http://$host:8080" 2>/dev/null)" = release-81; then
    printf '%s\n' "$host:8080 = release-81: ✗ [DQ:http_$n]"; failed=1
  fi
done
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
