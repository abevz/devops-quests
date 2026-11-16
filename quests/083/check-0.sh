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
dq_failed=0
set +e
(
set -euo pipefail
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY'
source platform.env
umask 077
headers=$(mktemp -d)
trap 'rm -f "$headers/reader" "$headers/manager"; rmdir "$headers"' EXIT
printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN" > "$headers/reader"
failed=0
if ! test "$(curl -fsS -H @"$headers/reader" "$VAULT_ADDR/v1/secret/data/dispatch" 2>/dev/null | jq -er .data.data.value 2>/dev/null)" = north-secret; then
  printf '%s\n' 'reader secret/data/dispatch value = north-secret: ✗ [DQ:reader]'
  failed=1
fi

if ! test "$(kubectl get secret route-secret -o jsonpath='{.data.value}' 2>/dev/null | base64 -d 2>/dev/null)" = north-secret; then
  printf '%s\n' 'Secret route-secret value = north-secret: ✗ [DQ:secret]'
  failed=1
fi

if ! test "$(kubectl exec deployment/relay -c worker -- printenv ROUTE_SECRET 2>/dev/null)" = north-secret; then
  printf '%s\n' 'deployment/relay ROUTE_SECRET = north-secret: ✗ [DQ:env]'
  failed=1
fi
exit "$failed"
DQ_LEGACY
)
[ $? -eq 0 ] || dq_failed=1
(
set -euo pipefail
timeout --kill-after=1s 14s bash -euo pipefail <<'DQ_CURRENT'
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
python3 -I - <<'DQ_VAULT_APPLICATION'

import hashlib,json,stat,urllib.request
from pathlib import Path
facts=json.loads(Path('/run/dq/facts/0/consumer-contract.json').read_text())
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
def read(path,limit=8192):
 p=Path(path); s=p.lstat()
 assert stat.S_ISREG(s.st_mode) and s.st_size<=limit
 return p.read_bytes()
def process(role):
 old=facts[role]
 assert read(role+'/application.pid').decode().strip()==str(old['pid'])
 proc=Path('/proc')/str(old['pid'])
 fields=(proc/'stat').read_text().rsplit(') ',1)[1].split()
 assert fields[0] not in ('Z','X') and fields[19]==old['start']
 assert (proc/'cmdline').read_bytes().hex()==old['command']
 status=dict(line.split(':',1) for line in (proc/'status').read_text().splitlines() if ':' in line)
 assert all(status[k].strip()==v for k,v in old['status'].items())
 assert hashlib.sha256(read('provided-vault-consumer.py',65536)).hexdigest()==facts['program_sha256']
def response(port):
 with opener.open('http://127.0.0.1:'+str(port)+'/',timeout=2) as r:
  data=json.load(r)
 assert data.get('ready') is True
 assert data.get('value_sha256')==facts['value_sha256']
 assert type(data.get('version')) is int and data['version']==facts['version']
 return data
process('consumer')
config=json.loads(read('consumer/source.json',4096))
assert set(config)=={'url','path','token_file'}
assert config['url']==facts['vault_url'] and config['path']==facts['path']
credential=Path(config['token_file'])
assert stat.S_IMODE(credential.lstat().st_mode)==0o600
assert credential.lstat().st_uid==1000
assert hashlib.sha256(read(credential,4096).strip()).hexdigest()==facts['reader_sha256']
data=response(18081)
assert data.get('kind')=='vault' and data.get('source')==facts['vault_url'] and data.get('path')==facts['path']

DQ_VAULT_APPLICATION
source platform.env
curl -fsS --max-time 2 -H @<(printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN") -H 'Content-Type: application/json' -X POST --data '{"paths":["secret/data/dispatch","secret/data/other","sys/audit"]}' "$VAULT_ADDR/v1/sys/capabilities-self" | jq -e '."secret/data/dispatch"==["read"] and ."secret/data/other"==["deny"] and ."sys/audit"==["deny"]' >/dev/null

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

DQ_CURRENT
)
[ $? -eq 0 ] || dq_failed=1
set -e
test "$dq_failed" -eq 0
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
dq_failed=0
set +e
(
set -euo pipefail
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY'
failed=0
if ! kubectl rollout status deployment/relay --timeout=3s >/dev/null 2>&1; then
  printf '%s\n' 'deployment/relay rollout → 0: ✗ [DQ:rollout]'
  failed=1
fi
exit "$failed"
DQ_LEGACY
)
[ $? -eq 0 ] || dq_failed=1
(
set -euo pipefail
timeout --kill-after=1s 14s bash -euo pipefail <<'DQ_CURRENT'
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
python3 -I - <<'DQ_VAULT_APPLICATION'

import json,subprocess
from pathlib import Path
def kubectl(*args):
 return subprocess.check_output(['kubectl',*args],timeout=3)
old=json.loads(Path('/run/dq/facts/0/original-relay.json').read_text())
current=json.loads(kubectl('get','deployment','relay','-o','json'))
assert current['metadata']['uid']==old['metadata']['uid']
assert current['spec']['template']['spec']==old['spec']['template']['spec']
assert current['spec']['selector']==old['spec']['selector']
assert current['spec'].get('replicas',1)==old['spec'].get('replicas',1)==1
rs=json.loads(kubectl('get','replicasets','-o','json'))['items']
owned={x['metadata']['uid'] for x in rs if any(o.get('controller') is True and o['uid']==old['metadata']['uid'] for o in x['metadata'].get('ownerReferences',[]))}
pods=json.loads(kubectl('get','pods','-o','json'))['items']
active=[p for p in pods if not p['metadata'].get('deletionTimestamp') and p['status'].get('phase') not in ('Succeeded','Failed') and any(o.get('controller') is True and o['uid'] in owned for o in p['metadata'].get('ownerReferences',[]))]
assert len(active)==1
for p in active:
 assert p['spec']['containers'][0]['image']==old['spec']['template']['spec']['containers'][0]['image']
 assert any(c['type']=='Ready' and c['status']=='True' for c in p['status'].get('conditions',[]))
 assert kubectl('exec',p['metadata']['name'],'-c','worker','--','printenv','ROUTE_SECRET').strip()==b'north-secret'

DQ_VAULT_APPLICATION

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

DQ_CURRENT
)
[ $? -eq 0 ] || dq_failed=1
set -e
test "$dq_failed" -eq 0
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
exit "$failed"
