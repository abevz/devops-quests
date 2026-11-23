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
jq -e --slurpfile events /run/dq/facts/0/audit-events.json 'keys==["operation","path","reason","request_id"] and .==$events[0][0]' incident.json >/dev/null
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

import json
from pathlib import Path
events=json.loads(Path('/run/dq/facts/0/consumer-audit.json').read_text())
report=json.loads(Path('consumer-incident.json').read_text())
assert set(report)=={'baseline','application'}
expected={e['path']:e for e in events}
assert len(events)==len(expected)==2
assert report['baseline']==expected['secret/data/dispatch']
assert report['application']==expected['secret/dispatch']
assert all(set(e)=={'request_id','path','operation','reason'} for e in report.values())

DQ_VAULT_APPLICATION

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
set +e
(
set -e
source platform.env
curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" -H 'Content-Type: application/json' --request POST --data '{"paths":["secret/data/dispatch","secret/data/other","sys/audit"]}' "$VAULT_ADDR/v1/sys/capabilities-self" | jq -e '."secret/data/dispatch"==["read"] and ."secret/data/other"==["deny"] and ."sys/audit"==["deny"]' >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The narrow Vault path capabilities could not be verified: ✗ [DQ:vault_capabilities]' >&2
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
dq_failed=0
set +e
(
set -euo pipefail
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY'
source platform.env
test "$(curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" "$VAULT_ADDR/v1/secret/data/dispatch" | jq -er .data.data.value)" = north-secret
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
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_2]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0

)
[ $? -eq 0 ] || failed=1
exit "$failed"
