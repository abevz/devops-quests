set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
status=$(curl -fsS "$VAULT_ADDR/v1/sys/seal-status" 2>/dev/null || true)
failed=0
if ! jq -e '.initialized == true' <<<"$status" >/dev/null 2>&1; then
  printf '%s\n' 'sys/seal-status initialized = true: ✗ [DQ:initialized]'
  failed=1
fi

if ! jq -e '.sealed == false' <<<"$status" >/dev/null 2>&1; then
  printf '%s\n' 'sys/seal-status sealed = false: ✗ [DQ:sealed]'
  failed=1
fi

if ! test -s /run/dq/facts/0/original-cluster-id || ! jq -e --arg id "$(cat /run/dq/facts/0/original-cluster-id 2>/dev/null)" '.cluster_id == $id' <<<"$status" >/dev/null 2>&1; then
  printf '%s\n' 'cluster_id = /run/dq/facts/0/original-cluster-id: ✗ [DQ:cluster]'
  failed=1
fi

if ! jq -e '.t == 2' <<<"$status" >/dev/null 2>&1; then
  printf '%s\n' 'sys/seal-status t = 2: ✗ [DQ:threshold]'
  failed=1
fi

if ! jq -e '.n == 3' <<<"$status" >/dev/null 2>&1; then
  printf '%s\n' 'sys/seal-status n = 3: ✗ [DQ:shares]'
  failed=1
fi
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
printf 'X-Vault-Token: %s\n' "$VAULT_MANAGER_TOKEN" > "$headers/manager"
failed=0
if ! test "$(curl -fsS -H @"$headers/reader" "$VAULT_ADDR/v1/secret/data/dispatch" 2>/dev/null | jq -er .data.data.value 2>/dev/null)" = north-secret; then
  printf '%s\n' 'reader secret/data/dispatch value = north-secret: ✗ [DQ:reader]'
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

process('downstream')
config=json.loads(read('downstream/source.json',4096))
assert config=={'upstream':'http://127.0.0.1:18081'}
data=response(18082)
assert data.get('kind')=='consumer' and data.get('source')=='http://127.0.0.1:18081'

DQ_VAULT_APPLICATION

) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_1]'
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
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_1]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0

)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
umask 077
headers=$(mktemp -d)
trap 'rm -f "$headers/reader" "$headers/manager"; rmdir "$headers"' EXIT
printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN" > "$headers/reader"
printf 'X-Vault-Token: %s\n' "$VAULT_MANAGER_TOKEN" > "$headers/manager"
failed=0
if ! test "$(curl -sS -o /dev/null -w '%{http_code}' -H @"$headers/manager" "$VAULT_ADDR/v1/secret/data/dispatch" 2>/dev/null)" = 403; then
  printf '%s\n' 'manager secret/data/dispatch HTTP = 403: ✗ [DQ:manager]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! test "$(stat -c %a unseal-shares.json 2>/dev/null)" = 600; then
  printf '%s\n' 'unseal-shares.json mode = 0600: ✗ [DQ:mode]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
