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
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 /srv/site/message: content = north-ready : ✗ [DQ:content_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 /srv/site/message: content = north-ready : ✗ [DQ:content_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 /srv/site/message: content = north-ready : ✗ [DQ:content_3]'
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
timeout --kill-after=1s 10s bash -euo pipefail <<'DQ_LEGACY_052'
dq_group_failed=0
set +e
(
set -e
test "$(curl -fsS --max-time 3 http://app1-${DQ_NAMESPACE#dq-}:8080)" = north-ready
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 HTTP / on port 8080 = north-ready : ✗ [DQ:http_1]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app2-${DQ_NAMESPACE#dq-}:8080)" = north-ready
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 HTTP / on port 8080 = north-ready : ✗ [DQ:http_2]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app3-${DQ_NAMESPACE#dq-}:8080)" = north-ready
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 HTTP / on port 8080 = north-ready : ✗ [DQ:http_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
DQ_LEGACY_052
python3 -I - <<'DQ_CONSUMERS'
import json, os, shlex, subprocess, sys, time, urllib.request
from pathlib import Path

deadline = time.monotonic() + 10
observer = "import hashlib\nimport json\nimport sys\nfrom pathlib import Path\n\nresult = {}\nfor item in json.loads(sys.argv[1]):\n    pid = Path(item['pidFile']).read_text().strip()\n    proc = Path('/proc') / pid\n    status = dict(line.split(':', 1) for line in (proc / 'status').read_text().splitlines() if ':' in line)\n    result[item['name']] = {\n        'pid': pid,\n        'starttime': (proc / 'stat').read_text().rsplit(') ', 1)[1].split()[19],\n        'uid': status['Uid'].split(),\n        'gid': status['Gid'].split(),\n        'groups': status['Groups'].split(),\n        'caps': {key: status[key].strip() for key in ('CapInh', 'CapPrm', 'CapEff', 'CapBnd', 'CapAmb')},\n        'command': (proc / 'cmdline').read_bytes().decode().split(chr(0)),\n        'code': hashlib.sha256(Path(item['programPath']).read_bytes()).hexdigest(),\n    }\nprint(json.dumps(result))\n"
facts = Path('/run/dq/facts/0')
try:
    contract = json.loads((facts / 'consumer-contract.json').read_text())
    expected = json.loads((facts / 'consumer-identities.json').read_text())
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    for host in ('app1', 'app2', 'app3'):
        address = host + '-' + os.environ['DQ_NAMESPACE'][3:]
        remote = '/usr/bin/python3 -c ' + shlex.quote(observer) + ' ' + shlex.quote(json.dumps(contract['consumers']))
        result = subprocess.run(['ssh', '-n', '-o', 'BatchMode=yes', '-p', '2222', 'root@' + address, remote], check=True, capture_output=True, text=True, timeout=max(.01, deadline-time.monotonic()))
        if json.loads(result.stdout) != expected[host]:
            print('Provided application identity changed: ✗ [DQ:consumer_identity]')
            sys.exit(1)
        for item in contract['consumers']:
            with opener.open('http://' + address + ':' + str(item['port']) + '/', timeout=max(.01, deadline-time.monotonic())) as response:
                if response.read(65536).decode().strip() != contract['response']:
                    print('Live application cache is stale: ✗ [DQ:consumer_cache]')
                    sys.exit(1)
except subprocess.TimeoutExpired:
    print('Application observation timed out: ✗ [DQ:consumer_budget]')
    sys.exit(1)
except (OSError, ValueError, KeyError, subprocess.CalledProcessError):
    print('Application could not be observed: ✗ [DQ:consumer_observation]')
    sys.exit(1)
DQ_CONSUMERS
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
