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
test "$(sha256sum recovery.tar | cut -d' ' -f1)" = "$(cat /run/dq/facts/0/artifact.sha256)"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Workstation ~/quest/recovery.tar matches the trusted frozen receipt : ✗ [DQ:artifact]'
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
python3 -I - <<'VERIFY'
import shlex
import yaml

MODULES = {'copy', 'file', 'stat', 'command', 'assert', 'unarchive', 'template', 'debug', 'fail', 'set_fact', 'meta'}
KEYWORDS = {'name', 'args', 'action', 'local_action', 'notify', 'listen', 'register', 'tags', 'vars', 'delegate_to', 'delegate_facts', 'run_once', 'no_log', 'become', 'become_user', 'environment', 'when', 'changed_when', 'failed_when', 'check_mode', 'ignore_errors', 'ignore_unreachable', 'until', 'retries', 'delay', 'loop', 'with_items', 'loop_control', 'throttle', 'timeout', 'connection', 'collections', 'any_errors_fatal', 'diff'}

def names(value):
    if value is None: return []
    if isinstance(value, str): return [part.strip() for part in value.split(',') if part.strip()]
    assert isinstance(value, list) and all(isinstance(part, str) for part in value)
    return value

def fleet(play):
    hosts = play.get('hosts')
    return hosts in ('fleet', ['fleet']) or (isinstance(hosts, list) and set(hosts) == {'app1', 'app2', 'app3'})

def builtin_module(value, collections=None):
    assert isinstance(value,str)
    if value in MODULES:
        assert not collections or collections=='ansible.builtin' or (isinstance(collections,list) and all(item=='ansible.builtin' for item in collections)), 'A short alias must resolve to a builtin module'
        return value
    assert value.startswith('ansible.builtin.') and value.removeprefix('ansible.builtin.') in MODULES, 'Unknown collection modules cannot certify builtin effects'
    return value.removeprefix('ansible.builtin.')

def action(task):
    assert isinstance(task, dict)
    direct = [key for key in task if key.rsplit('.', 1)[-1] in MODULES]
    explicit = [key for key in ('action', 'local_action') if key in task]
    assert len(direct) + len(explicit) == 1, 'Exactly one module action per task'
    assert all(key in KEYWORDS or key in direct for key in task), 'Unknown task action'
    if direct:
        key = direct[0]; module = builtin_module(key,task.get('collections')); args = task[key]
    else:
        declaration = task[explicit[0]]
        if isinstance(declaration, dict):
            args = dict(declaration); module = builtin_module(args.pop('module'),task.get('collections'))
        else:
            parts = shlex.split(declaration); module = builtin_module(parts.pop(0),task.get('collections'))
            args = ' '.join(parts) if module == 'command' else dict(part.split('=', 1) for part in parts)
    assert module in MODULES
    if args is None: args = {}
    if isinstance(args, str):
        args = {'_raw_params': args} if module in ('command', 'meta') else dict(part.split('=', 1) for part in shlex.split(args))
    assert isinstance(args, dict)
    args = {**args, **task.get('args', {})}
    return module, args

def tasks(items, inherited=None):
    inherited = inherited or {}
    for task in items or []:
        assert isinstance(task, dict)
        merged = {**inherited, **task}
        merged['tags'] = names(inherited.get('tags')) + names(task.get('tags'))
        merged['vars'] = {**inherited.get('vars', {}), **task.get('vars', {})}
        if 'block' in task:
            context = {key: merged[key] for key in KEYWORDS if key in merged and key not in ('name', 'action', 'local_action', 'args')}
            yield from tasks(task['block'], context)
            yield from tasks(task.get('rescue', []), context)
            yield from tasks(task.get('always', []), context)
        else:
            yield merged

def plays():
    data = yaml.safe_load(open('rollout.yml'))
    assert isinstance(data, list) and data and all(isinstance(play, dict) and fleet(play) for play in data)
    assert all(not play.get('roles') for play in data), 'Role effects are outside the certified task workflow'
    return data

def flat(play):
    context = {key: play[key] for key in ('no_log', 'check_mode', 'tags', 'vars', 'delegate_to', 'run_once', 'when', 'collections') if key in play}
    return list(tasks(play.get('pre_tasks', []) + play.get('tasks', []) + play.get('post_tasks', []), context))

def unconditional(task):
    assert not any(task.get(key) not in (None, [], True, 'true', 'True') for key in ('when',))
    assert not any(key in task for key in ('loop', 'with_items', 'until', 'ignore_errors', 'ignore_unreachable', 'failed_when'))

from pathlib import Path
import ast
import re
expected=Path('/run/dq/facts/0/artifact.sha256').read_text().strip()
assert len(expected)==64 and all(char in '0123456789abcdef' for char in expected)

def equality(expression,actual,variables,registered):
 tree=ast.parse(expression,mode='eval').body
 assert isinstance(tree,ast.Compare) and len(tree.ops)==1 and isinstance(tree.ops[0],ast.Eq) and len(tree.comparators)==1
 def operand(node):
  if isinstance(node,ast.Name):return variables.get(node.id)
  if isinstance(node,ast.Constant):return node.value
  if isinstance(node,ast.Attribute) and node.attr=='checksum' and isinstance(node.value,ast.Attribute) and node.value.attr=='stat' and isinstance(node.value.value,ast.Name) and node.value.value.id==registered:return actual
  if isinstance(node,ast.Subscript) and isinstance(node.slice,ast.Constant) and node.slice.value=='checksum' and isinstance(node.value,ast.Subscript) and isinstance(node.value.slice,ast.Constant) and node.value.slice.value=='stat' and isinstance(node.value.value,ast.Name) and node.value.value.id==registered:return actual
  raise AssertionError('Compare the complete observed checksum with the trusted SHA256')
 return operand(tree.left)==operand(tree.comparators[0])

def boolean(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        if value.lower() in ('true', 'yes', 'on', '1'): return True
        if value.lower() in ('false', 'no', 'off', '0'): return False
    if type(value) is int and value in (0, 1): return bool(value)
    return None



def command(args):
    if 'argv' in args:
        assert isinstance(args['argv'], list) and all(isinstance(part, str) for part in args['argv'])
        return args['argv']
    return shlex.split(args.get('_raw_params', args.get('cmd', '')))



def reload_handler(play, task, expected='dq-service'):
    notified = names(task.get('notify'))
    assert notified, 'The changed file must notify a reload'
    handlers = list(tasks(play.get('handlers', []), {'collections':play.get('collections')}))
    selected = [handler for handler in handlers if set(notified) & ({handler.get('name')} | set(names(handler.get('listen'))))]
    assert selected and all(any(name in ({h.get('name')} | set(names(h.get('listen')))) for h in selected) for name in notified)
    for handler in selected:
        unconditional(handler)
        module, args = action(handler)
        assert module == 'command' and command(args) == [expected, 'reload']
        assert set(args) <= {'argv', 'cmd', '_raw_params', 'expand_argument_vars', 'strip_empty_ends'}


def failure_context(items, inherited=False):
 for task in items or []:
  assert not task.get('module_defaults'), 'Opaque block defaults cannot change the certified archive source'
  caught=inherited or ('ignore_errors' in task and boolean(task['ignore_errors']) is not False)
  if 'block' in task:
   # An always/rescue branch can run after the assertion fails. We certify only
   # guards whose failure unconditionally stops before every extraction.
   caught=caught or bool(task.get('rescue')) or bool(task.get('always'))
   for key in ('block','rescue','always'):
    yield from failure_context(task.get(key,[]),caught)
  else:yield caught

verified=False
sealed=False
for play in plays():
 assert not play.get('vars_files') and not play.get('vars_prompt') and not play.get('module_defaults'), 'External bindings are outside the certified checksum workflow'
 for handler in tasks(play.get('handlers',[])):
  assert not names(handler.get('notify')), 'Handler notification chains are outside the certified workflow'
  labels=names(handler.get('name'))+names(handler.get('listen'))
  assert not any(mark in label for label in labels for mark in ('{{','{%','{#')), 'Handler identities must be statically resolvable'
 ordered=flat(play);hashes=[]
 contexts=list(failure_context(play.get('pre_tasks',[])+play.get('tasks',[])+play.get('post_tasks',[]), 'ignore_errors' in play and boolean(play['ignore_errors']) is not False))
 assert len(contexts)==len(ordered)
 for position,task in enumerate(ordered):
  module,args=action(task)
  # Registers refer to the latest task result, never an earlier stat.
  if 'register' in task:
   hashes=[item for item in hashes if item[1]!=task['register']]
  if names(task.get('notify')):
   assert module=='unarchive' and verified, 'Only verified extraction may notify a certified service reload'
   reload_handler(play,task)
  assert not re.search(r'\b(?:lookup|query|q)\s*\(',yaml.safe_dump(task)), 'Side-effecting lookups cannot certify archive integrity'
  if not verified: assert module in ('stat','assert','debug','fail','command','unarchive'), 'Only read-only prechecks may precede checksum verification'
  if not verified and module in ('copy','template','file'):
   destination=args.get('dest',args.get('path',''))
   assert isinstance(destination,str) and '{{' not in destination and destination.rstrip('/')!='/srv/site/message', 'Do not change the restoration target before verification'
  if not verified and module=='command':
   assert command(args) and command(args)[0] in ('cat','sha256sum','stat','/bin/cat','/usr/bin/cat'), 'Only read-only prechecks may precede verification'
  if sealed:
   assert module in ('stat','assert','debug','fail','unarchive'), 'Do not mutate the archive or checksum bindings after collecting its checksum'
   assert not re.search(r'\b(?:lookup|query|q)\s*\(',yaml.safe_dump(task)), 'Side-effecting template lookups cannot certify archive integrity'
  if module=='unarchive':
   assert verified, 'Reject archive extraction before trusted-checksum verification in every play'
   # The builtin action searches files/ before the playbook directory for bare src.
   # Accept a shadow only when its bytes are the same trusted archive.
   if args.get('src')=='recovery.tar' and Path('files/recovery.tar').exists():
    import hashlib
    assert hashlib.sha256(Path('files/recovery.tar').read_bytes()).hexdigest()==expected, 'The archive selected by the action must match the trusted receipt'
  if module=='stat' and args.get('checksum_algorithm')=='sha256':
   path=args.get('path')
   if path in ('recovery.tar','{{ playbook_dir }}/recovery.tar',str(Path.cwd() / 'recovery.tar')):
    if contexts[position]:continue
    tags=names(task.get('tags'))
    assert not any(mark in tag for tag in tags for mark in ('{{','{%','{#'))
    if 'never' in tags and 'always' not in tags:continue
    sealed=True
    unconditional(task)
    assert 'local_action' in task or task.get('delegate_to') in ('localhost','127.0.0.1','::1')
    assert isinstance(task.get('register'),str)
    hashes.append((position,task['register']))
  if module=='assert':
   if contexts[position]:continue
   tags=names(task.get('tags'))
   assert not any(mark in tag for tag in tags for mark in ('{{','{%','{#'))
   if 'never' in tags and 'always' not in tags:continue
   unconditional(task)
   expressions=args.get('that',[]);expressions=[expressions] if isinstance(expressions,str) else expressions
   assert isinstance(expressions,list) and expressions
   for hash_position,registered in hashes:
    variables=task.get('vars',{})
    if not any(value==expected for value in variables.values()):continue
    mismatches=['0'*64,'f'*64,expected[:-1]+('0' if expected[-1]!='0' else '1'),expected+'0',expected[:32]]
    try:
     good=all(equality(expression,expected,variables,registered) for expression in expressions)
     rejects=all(not all(equality(expression,bad,variables,registered) for expression in expressions) for bad in mismatches if bad!=expected)
    except (AssertionError,SyntaxError,TypeError):continue
    if good and rejects:
     # An archive extraction before verification invalidates the ordering guarantee.
     assert not any(action(prior)[0]=='unarchive' for prior in ordered[:position])
     verified=True
assert verified, 'Hash the trusted archive and reject every whole-checksum mismatch before restoring'
VERIFY
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
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
cd ~/quest
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY_RESTORE'
dq_result_failed=0
set +e
(
set -e
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-96'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 /srv/site/message: content = north-96 : ✗ [DQ:content_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-96'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 /srv/site/message: content = north-96 : ✗ [DQ:content_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-96'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 /srv/site/message: content = north-96 : ✗ [DQ:content_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || dq_result_failed=1
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
[ $? -eq 0 ] || dq_result_failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %u:%g /srv/site/message)" = 0:0'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 /srv/site/message: owner = 0:0 : ✗ [DQ:owner_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %u:%g /srv/site/message)" = 0:0'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 /srv/site/message: owner = 0:0 : ✗ [DQ:owner_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %u:%g /srv/site/message)" = 0:0'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 /srv/site/message: owner = 0:0 : ✗ [DQ:owner_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || dq_result_failed=1
set -e
test "$dq_result_failed" -eq 0
DQ_LEGACY_RESTORE
python3 -I - <<'DQ_RESTORE_IDENTITY'
import json
import os
import shlex
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

observer = "import hashlib\nimport json\nimport sys\nfrom pathlib import Path\n\nresult = {}\nfor item in json.loads(sys.argv[1]):\n    pid = Path(item['pidFile']).read_text().strip()\n    proc = Path('/proc') / pid\n    status = dict(line.split(':', 1) for line in (proc / 'status').read_text().splitlines() if ':' in line)\n    result[item['name']] = {\n        'pid': pid,\n        'starttime': (proc / 'stat').read_text().rsplit(') ', 1)[1].split()[19],\n        'uid': status['Uid'].split(),\n        'gid': status['Gid'].split(),\n        'groups': status['Groups'].split(),\n        'caps': {key: status[key].strip() for key in ('CapInh', 'CapPrm', 'CapEff', 'CapBnd', 'CapAmb')},\n        'command': (proc / 'cmdline').read_bytes().decode().split(chr(0)),\n        'code': hashlib.sha256(Path(item['programPath']).read_bytes()).hexdigest(),\n    }\nprint(json.dumps(result))\n"
file_observer = "import hashlib,json,stat\nfrom pathlib import Path\nresult={}\nfor name in ['consumer-binding.json','tenant.json']:\n p=Path('/srv/site')/name;s=p.stat();result[name]={'inode':s.st_ino,'mtime':s.st_mtime_ns,'mode':stat.S_IMODE(s.st_mode),'uid':s.st_uid,'gid':s.st_gid,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'json':json.loads(p.read_text())}\nprint(json.dumps(result))\n"
caller_program = 'import json,os,stat,subprocess,tempfile,time\nfrom pathlib import Path\nstart=time.monotonic()\nwith tempfile.TemporaryDirectory(prefix=\'.dq-restore-construction-\', dir=Path.cwd()) as folder:\n root=Path(folder);destination=root/\'live\';destination.mkdir();binary=root/\'bin\';binary.mkdir()\n message=destination/\'message\';binding=destination/\'consumer-binding.json\';ledger=destination/\'tenant.json\';cache=root/\'cache\';control=destination/\'retained-control\'\n message.write_text(\'retired-caller\\n\');cache.write_text(\'retired-caller\\n\');binding.write_text(json.dumps({\'pid\':91,\'instance\':\'caller-live\'})+\'\\n\');ledger.write_text(json.dumps({\'account\':\'caller\',\'balance\':4711})+\'\\n\');ledger.chmod(0o600);control.write_text(\'retain unrelated caller data\\n\')\n def state(path):\n  s=path.stat();return (s.st_ino,s.st_mtime_ns,stat.S_IMODE(s.st_mode),s.st_uid,s.st_gid,path.read_bytes())\n original={p:state(p) for p in [binding,ledger,control]}\n callback=binary/\'dq-service\';callback.write_text(\'#!/usr/bin/python3\\nimport sys\\nfrom pathlib import Path\\nassert sys.argv[1:] == ["reload"]\\nPath(\'+repr(str(cache))+\').write_bytes(Path(\'+repr(str(message))+\').read_bytes())\\n\');callback.chmod(0o555);assert os.access(callback,os.X_OK), \'Caller callback must use the existing executable workspace\'\n (root/\'ansible.cfg\').write_text(\'[defaults]\\ninterpreter_python=/usr/bin/python3\\n\')\n (root/\'inventory.json\').write_text(json.dumps({\'all\':{\'children\':{\'fleet\':{\'hosts\':{\'caller\':{\'ansible_connection\':\'local\',\'ansible_python_interpreter\':\'/usr/bin/python3\'}}}}}}))\n args={\'restore_root\':str(destination),\'restore_owner\':str(os.getuid()),\'restore_group\':str(os.getgid()),\'ansible_connection\':\'local\',\'ansible_python_interpreter\':\'/usr/bin/python3\',\'ansible_become\':False}\n r=subprocess.run([\'ansible-playbook\',\'-i\',str(root/\'inventory.json\'),str(Path(\'rollout.yml\').resolve()),\'-e\',json.dumps(args)],env=dict(os.environ,ANSIBLE_CONFIG=str(root/\'ansible.cfg\'),PATH=str(binary)+\':\'+os.environ[\'PATH\']),capture_output=True,text=True,timeout=max(.01,deadline-time.monotonic()))\n valid=r.returncode==0 and message.read_text()==\'north-96\\n\' and cache.read_bytes()==message.read_bytes() and all(p.is_file() and state(p)==before for p,before in original.items()) and stat.S_IMODE(message.stat().st_mode)==0o644 and message.stat().st_uid==os.getuid()\n if not valid:print(\'Current restore program did not satisfy caller effects: ✗ [DQ:restore_effects]\')\n raise SystemExit(not valid)\n'
deadline = time.monotonic() + 12
failed = False
facts = Path('/run/dq/facts/0')
active_index = None


def reject(marker):
    global failed
    print('Restore observation is unmet: ✗ [DQ:' + marker + ']')
    failed = True


def remaining():
    value = deadline - time.monotonic()
    if value <= 0:
        raise subprocess.TimeoutExpired('restore observation', 12)
    return value


def remote(address, programme, args=None):
    command = '/usr/bin/python3 -I -c ' + shlex.quote(programme)
    if args is not None:
        command += ' ' + shlex.quote(json.dumps(args))
    result = subprocess.run(['ssh', '-n', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=1', '-o', 'ConnectionAttempts=1', '-p', '2222', 'root@' + address, command], check=True, capture_output=True, text=True, timeout=remaining())
    return json.loads(result.stdout)


try:
    contract = json.loads((facts / 'application-contract.json').read_text())
    identities = json.loads((facts / 'original-application-identities.json').read_text())
    original = json.loads((facts / 'original-live-data.json').read_text())
    suffix = os.environ['DQ_NAMESPACE'][3:]
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    for active_index, host in enumerate(('app1', 'app2', 'app3'), 1):
        address = host + '-' + suffix
        if remote(address, observer, [contract['process']]) != identities[host]:
            reject('application_identity_' + str(active_index))
        current = remote(address, file_observer)
        for name in ('consumer-binding.json', 'tenant.json'):
            previous = original[host][name]
            value = current[name]
            metadata_matches = all(value.get(key) == previous[key] for key in ('uid', 'gid', 'mode'))
            if name == 'consumer-binding.json':
                content_matches = value.get('json') == previous['json']
                marker = 'live_binding_'
            else:
                content_matches = isinstance(value.get('json'), dict) and all(value['json'].get(key) == wanted for key, wanted in previous['json'].items())
                marker = 'live_data_'
            if not metadata_matches or not content_matches:
                reject(marker + str(active_index))
        try:
            with opener.open('http://' + address + ':' + str(contract['port']) + '/', timeout=remaining()) as response:
                value = json.loads(response.read(65536))
        except urllib.error.HTTPError:
            reject('application_ready_' + str(active_index))
            continue
        expected_binding = original[host]['consumer-binding.json']['json']
        expected_ledger = original[host]['tenant.json']['json']
        expected = {'message': 'north-96', 'instance': expected_binding['instance'], 'account': expected_ledger['account'], 'balance': expected_ledger['balance']}
        if any(value.get(key) != wanted for key, wanted in expected.items()):
            reject('application_ready_' + str(active_index))
    # Execute the current certified program with a caller-owned destination and service.
    scope = {'deadline': deadline}
    try:
        exec(compile(caller_program, 'restore-caller-effect', 'exec'), scope)
    except SystemExit as result:
        if result.code:
            failed = True
except subprocess.TimeoutExpired:
    reject('restore_budget')
except (KeyError, TypeError, ValueError, OSError, subprocess.SubprocessError, RuntimeError):
    reject('restore_observation' + ('_' + str(active_index) if active_index else ''))
sys.exit(int(failed))
DQ_RESTORE_IDENTITY
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
dq_group_failed=0
set +e
(
set -e
test "$(curl -fsS http://app1-${DQ_NAMESPACE#dq-}:8080)" = north-96
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 HTTP / on port 8080 = north-96 : ✗ [DQ:http_1]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS http://app2-${DQ_NAMESPACE#dq-}:8080)" = north-96
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 HTTP / on port 8080 = north-96 : ✗ [DQ:http_2]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS http://app3-${DQ_NAMESPACE#dq-}:8080)" = north-96
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 HTTP / on port 8080 = north-96 : ✗ [DQ:http_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
