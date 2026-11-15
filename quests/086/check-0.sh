set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = stable-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 /srv/site/message: content = stable-ready : ✗ [DQ:content_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = stable-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 /srv/site/message: content = stable-ready : ✗ [DQ:content_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = stable-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 /srv/site/message: content = stable-ready : ✗ [DQ:content_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 /srv/site/message: mode = 644 : ✗ [DQ:mode_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 /srv/site/message: mode = 644 : ✗ [DQ:mode_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 /srv/site/message: mode = 644 : ✗ [DQ:mode_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
cd ~/quest
timeout --kill-after=1s 10s bash -euo pipefail <<'DQ_LEGACY_PUBLICATION'
dq_group_failed=0
set +e
(
set -e
test "$(curl -fsS --max-time 3 http://app1-${DQ_NAMESPACE#dq-}:8080)" = stable-ready
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 HTTP / on port 8080 = stable-ready : ✗ [DQ:http_1]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app2-${DQ_NAMESPACE#dq-}:8080)" = stable-ready
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 HTTP / on port 8080 = stable-ready : ✗ [DQ:http_2]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app3-${DQ_NAMESPACE#dq-}:8080)" = stable-ready
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 HTTP / on port 8080 = stable-ready : ✗ [DQ:http_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
DQ_LEGACY_PUBLICATION
python3 -I - <<'DQ_PUBLICATION'
import hashlib
import json
import os
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

observer = "import hashlib\nimport json\nimport sys\nfrom pathlib import Path\n\nresult = {}\nfor item in json.loads(sys.argv[1]):\n    pid = Path(item['pidFile']).read_text().strip()\n    proc = Path('/proc') / pid\n    status = dict(line.split(':', 1) for line in (proc / 'status').read_text().splitlines() if ':' in line)\n    result[item['name']] = {\n        'pid': pid,\n        'starttime': (proc / 'stat').read_text().rsplit(') ', 1)[1].split()[19],\n        'uid': status['Uid'].split(),\n        'gid': status['Gid'].split(),\n        'groups': status['Groups'].split(),\n        'caps': {key: status[key].strip() for key in ('CapInh', 'CapPrm', 'CapEff', 'CapBnd', 'CapAmb')},\n        'command': (proc / 'cmdline').read_bytes().decode().split(chr(0)),\n        'code': hashlib.sha256(Path(item['programPath']).read_bytes()).hexdigest(),\n    }\nprint(json.dumps(result))\n"
deadline = time.monotonic() + 10
failed = False
facts = Path('/run/dq/facts/0')
active_index = None


def reject(marker):
    global failed
    print('Observed application contract is unmet: ✗ [DQ:' + marker + ']')
    failed = True


def remaining():
    value = deadline - time.monotonic()
    if value <= 0:
        raise subprocess.TimeoutExpired('application observation', 10)
    return value


def command(args):
    return subprocess.run(args, capture_output=True, text=True, check=True, timeout=remaining())


def addresses(host):
    programme = 'import json,socket,sys; print(json.dumps(sorted({item[4][0] for item in socket.getaddrinfo(sys.argv[1],None,type=socket.SOCK_STREAM)})))'
    return set(json.loads(command(['/usr/bin/python3', '-I', '-c', programme, host]).stdout))


try:
    contract = json.loads((facts / 'application-contract.json').read_text())
    original = json.loads((facts / 'original-application-identities.json').read_text())
    controller = Path(contract['controllerArtifact'])
    if hashlib.sha256(controller.read_bytes()).hexdigest() != contract['publication']['sha256']:
        reject('controller_artifact')
    headers = {}
    if contract['authentication']:
        import yaml
        token = yaml.safe_load((facts / 'credentials.yml').read_text())['reader_token']
        headers = {'Authorization': 'Bearer ' + token}
    suffix = os.environ['DQ_NAMESPACE'][3:]
    source_host = contract['sourceHost'] + '-' + suffix
    source_addresses = addresses(source_host)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    for active_index, host in enumerate(('app1', 'app2', 'app3'), 1):
        address = host + '-' + suffix
        remote = '/usr/bin/python3 -I -c ' + shlex.quote(observer) + ' ' + shlex.quote(json.dumps([contract['process']]))
        identity = json.loads(command(['ssh', '-n', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=1', '-o', 'ConnectionAttempts=1', '-p', '2222', 'root@' + address, remote]).stdout)
        if identity != original[host]:
            reject('application_identity_' + str(active_index))
        try:
            request = urllib.request.Request('http://' + address + ':' + str(contract['port']) + '/', headers=headers)
            with opener.open(request, timeout=remaining()) as response:
                value = json.loads(response.read(65536))
        except urllib.error.HTTPError:
            reject('application_ready_' + str(active_index))
            continue
        data = value.get('data') or {}
        if value.get('ready') is not True or value.get('role') != contract['roles'][host] or any(data.get(key) != wanted for key, wanted in contract['publication'].items()):
            reject('application_ready_' + str(active_index))
            continue
        if host == contract['sourceHost']:
            if data.get('origin') != 'local':
                reject('application_origin_' + str(active_index))
        else:
            origin = urllib.parse.urlsplit(data.get('origin', ''))
            if origin.scheme != 'http' or origin.port != contract['port'] or not origin.hostname or not (addresses(origin.hostname) & source_addresses):
                reject('application_origin_' + str(active_index))
except subprocess.TimeoutExpired:
    reject('application_budget')
except (KeyError, TypeError, ValueError, OSError, subprocess.SubprocessError, RuntimeError):
    reject('application_observation' + ('_' + str(active_index) if active_index else ''))
sys.exit(int(failed))
DQ_PUBLICATION
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
