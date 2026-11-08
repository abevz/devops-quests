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
printf '%s\n' 'On app1, /srv/site/message contains north-ready : ✗ [DQ:content_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/message contains north-ready : ✗ [DQ:content_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/message contains north-ready : ✗ [DQ:content_3]'
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
printf '%s\n' 'On app1, /srv/site/message has mode 0644 : ✗ [DQ:mode_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/message has mode 0644 : ✗ [DQ:mode_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/message has mode 0644 : ✗ [DQ:mode_3]'
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
set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_DELIVERY_OBSERVATION'
import base64
from concurrent.futures import ThreadPoolExecutor
import json
import os
import re
import shlex
import subprocess
import tempfile
import time

started = time.monotonic()
deadline = started + 22
cleanup_deadline = started + 24
def budget(limit=5):
    remaining = deadline - time.monotonic()
    if remaining <= 0: raise TimeoutError()
    return min(limit, remaining)

REMOTE_READ = "import base64,json,os; from pathlib import Path; p=Path('/srv/site/message'); s=p.stat(); print(json.dumps({'data':base64.b64encode(p.read_bytes()).decode(),'mode':s.st_mode,'uid':s.st_uid,'gid':s.st_gid,'mtime':s.st_mtime_ns,'ctime':s.st_ctime_ns,'link':os.readlink(p) if p.is_symlink() else None}))"
REMOTE_RESTORE = "import base64,json,os,sys; from pathlib import Path; p=Path('/srv/site/message'); old=json.loads(base64.b64decode(sys.argv[1])); link=old['link']; different=(p.is_symlink() and (link is None or os.readlink(p)!=link)) or (link is not None and not p.is_symlink()); different and p.unlink(missing_ok=True); link is not None and not p.is_symlink() and p.symlink_to(link); p.write_bytes(base64.b64decode(old['data'])); os.chown(p,old['uid'],old['gid']); os.chmod(p,old['mode'] & 0o7777); os.utime(p,ns=(old['mtime'],old['mtime']))"
def remote(host, code, argument=None):
    suffix = os.environ['DQ_NAMESPACE'].removeprefix('dq-')
    command = 'python3 -c '+shlex.quote(code)
    if argument is not None: command += ' '+shlex.quote(argument)
    result = subprocess.run(['ssh','-n','-o','BatchMode=yes','-p','2222','root@'+host+'-'+suffix,command],capture_output=True,text=True,timeout=budget(2))
    if result.returncode: raise RuntimeError('Unable to observe or restore banner')
    return result.stdout

def banners():
    with ThreadPoolExecutor(max_workers=3) as pool:
        return dict(pool.map(lambda host:(host,json.loads(remote(host,REMOTE_READ))),('app1','app2','app3')))

CALLBACK = "from ansible.plugins.callback import CallbackBase\nimport base64,json,os,subprocess\nfrom concurrent.futures import ThreadPoolExecutor\nclass CallbackModule(CallbackBase):\n    CALLBACK_VERSION = 2.0\n    CALLBACK_TYPE = 'aggregate'\n    CALLBACK_NAME = 'dq_batch_observer'\n    CALLBACK_NEEDS_ENABLED = True\n    previous = None\n    def record(self):\n        if self.previous is None: return\n        def observe(host):\n            suffix = os.environ['DQ_NAMESPACE'].removeprefix('dq-')\n            value = subprocess.run(['ssh','-n','-o','BatchMode=yes','-o','ConnectTimeout=2','-p','2222','root@'+host+'-'+suffix,'cat /srv/site/message'],capture_output=True,timeout=3)\n            if value.returncode: raise RuntimeError('Cannot observe delivered file')\n            return host,base64.b64encode(value.stdout).decode()\n        with ThreadPoolExecutor(max_workers=3) as pool:\n            values = dict(pool.map(observe,('app1','app2','app3')))\n        with open(os.environ['DQ_BATCH_OBSERVATION'],'a') as output:\n            output.write(json.dumps({'batch':self.previous,'values':values})+'\\n')\n    def v2_playbook_on_play_start(self, play):\n        self.record()\n        inventory = play.get_variable_manager()._inventory\n        self.previous = [host.get_name() for host in inventory.get_hosts(play.hosts)]\n    def v2_playbook_on_stats(self, stats):\n        self.record()\n"

original = None
try:
    original = banners()
    sentinel = base64.b64encode(b'dq-delivery-observation\n').decode()
    def prepare(item):
        host, value = item
        changed = dict(value, data=sentinel)
        remote(host,REMOTE_RESTORE,base64.b64encode(json.dumps(changed).encode()).decode())
    with ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(prepare,original.items()))
    with tempfile.TemporaryDirectory() as directory:
        from pathlib import Path
        plugin = Path(directory)/'dq_batch_observer.py'
        plugin.write_text(CALLBACK)
        observations = Path(directory)/'batches.jsonl'
        environment = dict(os.environ,ANSIBLE_PIPELINING='1',ANSIBLE_CALLBACK_PLUGINS=directory,ANSIBLE_CALLBACKS_ENABLED='dq_batch_observer',DQ_BATCH_OBSERVATION=str(observations))
        with tempfile.TemporaryFile(mode='w+') as output:
            run = subprocess.run(['ansible-playbook','rollout.yml'],env=environment,stdout=output,stderr=subprocess.STDOUT,timeout=budget(20))
        if run.returncode: raise RuntimeError('Delivery did not complete')
        events = [json.loads(line) for line in observations.read_text().splitlines() if line.strip()]
    previous = {host:sentinel for host in original}
    delivered = []
    for event in events:
        values = event['values']
        changed = [host for host in original if values[host] != previous[host]]
        if changed:
            if len(changed) != 1 or event['batch'] != changed:
                raise RuntimeError('Delivery changed more than one host per batch')
            host = changed[0]
            if base64.b64decode(values[host]).rstrip(b'\n') != b'north-ready':
                raise RuntimeError('Delivery did not write the required message')
            delivered.append(host)
        previous = values
    if delivered != ['app1','app2','app3']:
        raise RuntimeError('Delivery order differs from the required progression')
except Exception as error:
    detail = str(error) if isinstance(error, RuntimeError) else type(error).__name__
    print('Delivery observation did not verify the required progression ('+detail+'): ✗ [DQ:delivery_trace]')
    raise SystemExit(1)
finally:
    deadline = cleanup_deadline
    if original is not None:
        def restore(item):
            host,value=item
            remote(host,REMOTE_RESTORE,base64.b64encode(json.dumps(value).encode()).decode())
        with ThreadPoolExecutor(max_workers=3) as pool:
            list(pool.map(restore,original.items()))

DQ_DELIVERY_OBSERVATION
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
