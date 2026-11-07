set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
if ! sha256sum -c previous.sha256 >/dev/null 2>&1; then printf '%s\n' 'previous.txt matches previous.sha256: ✗ [DQ:checksum]'; exit 1; fi
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = stable-63'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 /srv/site/message: content = stable-63 : ✗ [DQ:content_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = stable-63'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 /srv/site/message: content = stable-63 : ✗ [DQ:content_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = stable-63'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 /srv/site/message: content = stable-63 : ✗ [DQ:content_3]'
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
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 /srv/site/message: mode = 644 : ✗ [DQ:mode_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 /srv/site/message: mode = 644 : ✗ [DQ:mode_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
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
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/recovery-checked)" = checked'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 /srv/site/recovery-checked: content = checked : ✗ [DQ:marker_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/recovery-checked)" = checked'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 /srv/site/recovery-checked: content = checked : ✗ [DQ:marker_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/recovery-checked)" = checked'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 /srv/site/recovery-checked: content = checked : ✗ [DQ:marker_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_result_failed=0
set +e
(
set -e
python3 -I - <<'SCOPE'
import shlex
import yaml

MODULES = {'copy', 'file', 'stat', 'command', 'assert', 'unarchive', 'template', 'debug', 'fail', 'set_fact', 'meta'}
KEYWORDS = {'name', 'args', 'action', 'local_action', 'notify', 'listen', 'register', 'tags', 'vars', 'delegate_to', 'delegate_facts', 'run_once', 'no_log', 'become', 'become_user', 'environment', 'when', 'changed_when', 'failed_when', 'check_mode', 'ignore_errors', 'ignore_unreachable', 'until', 'retries', 'delay', 'loop', 'with_items', 'loop_control', 'throttle', 'timeout', 'connection', 'collections', 'any_errors_fatal', 'diff'}

def boolean(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        if value.lower() in ('true', 'yes', 'on', '1'): return True
        if value.lower() in ('false', 'no', 'off', '0'): return False
    if type(value) is int and value in (0, 1): return bool(value)
    return None

def mode(value):
    if isinstance(value, bool): return None
    if isinstance(value, int): return value
    try: return int(str(value), 8)
    except (TypeError, ValueError): return None

def names(value):
    if value is None: return []
    if isinstance(value, str): return [part.strip() for part in value.split(',') if part.strip()]
    assert isinstance(value, list) and all(isinstance(part, str) for part in value)
    return value

def fleet(play):
    hosts = play.get('hosts')
    return hosts in ('fleet', ['fleet']) or (isinstance(hosts, list) and set(hosts) == {'app1', 'app2', 'app3'})

import json
import subprocess
from functools import lru_cache


@lru_cache(maxsize=1)
def inventory_data():
    return json.loads(subprocess.check_output(
        ['ansible-inventory', '--list'], text=True, timeout=3))


def selected_host_count(hosts):
    data = inventory_data()
    def group(name, seen=None):
        seen = set() if seen is None else seen
        if name in seen: return set()
        seen.add(name)
        entry = data.get(name, {})
        found = set(entry.get('hosts', []))
        for child in entry.get('children', []): found |= group(child, seen)
        return found
    if hosts == 'fleet' or hosts == ['fleet']:
        return len(group('fleet'))
    return len(set(hosts) & group('all'))


def one_at_a_time(value, hosts='fleet'):
    batches = value if isinstance(value, list) else [value]
    if not batches or value is None: return False
    def number(item, total):
        if isinstance(item, bool): raise ValueError('A boolean is not a batch count')
        if isinstance(item, str) and item.endswith('%'):
            # Match the pinned Ansible executor's pct_to_int exactly: integer
            # percentages, total selected hosts, minimum one for a rounded zero.
            percentage = int(item[:-1])
            return int((percentage / 100.0) * total) or 1
        if isinstance(item, float) and not item.is_integer(): raise ValueError('Integer batch count required')
        return int(item)
    try:
        if all(not isinstance(item, bool) and not (isinstance(item, str) and item.endswith('%')) and number(item, 1) == 1 for item in batches):
            return True
        total = selected_host_count(hosts)
        if total <= 0: return False
        remaining = total
        index = 0
        while remaining:
            requested = number(batches[min(index, len(batches)-1)], total)
            actual = remaining if requested <= 0 else min(requested, remaining)
            if actual != 1: return False
            remaining -= actual
            index += 1
        return True
    except (ValueError, TypeError, OSError, subprocess.SubprocessError, AttributeError, KeyError):
        return False


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
        else:
            yield merged

def plays():
    data = yaml.safe_load(open('rollout.yml'))
    assert isinstance(data, list) and data and all(isinstance(play, dict) and fleet(play) for play in data)
    return data

def command(args):
    if 'argv' in args:
        assert isinstance(args['argv'], list) and all(isinstance(part, str) for part in args['argv'])
        return args['argv']
    parts = shlex.split(args.get('_raw_params', args.get('cmd', '')))
    if parts and parts[0] in ('/bin/cat','/usr/bin/cat','/usr/local/bin/dq-service'):
        parts[0] = parts[0].rsplit('/',1)[-1]
    if len(parts)>1 and parts[0]=='cat' and parts[1]=='--': parts.pop(1)
    return parts

def unconditional(task):
    assert not any(task.get(key) not in (None, [], True, 'true', 'True') for key in ('when',))
    assert not any(key in task for key in ('loop', 'with_items', 'until', 'ignore_errors', 'ignore_unreachable', 'failed_when'))

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

import sys
try:
 data=plays()
 choices=[(play,task) for play in data for task in play.get('tasks',[]) if isinstance(task,dict) and 'block' in task]
 play,task=next(((play,task) for play,task in choices if task.get('rescue')), choices[0] if choices else (data[0],{}))
 scope={key:play[key] for key in KEYWORDS if key in play}
 scope.update({key:task[key] for key in KEYWORDS if key in task})
 unconditional(scope)
 assert 'check_mode' not in scope or boolean(scope['check_mode']) is False
 assert 'changed_when' not in scope
 candidates=[]
 for candidate in tasks(task.get('rescue',[]),scope):
  module,args=action(candidate)
  if module=='copy' and args.get('dest')=='/srv/site/message': candidates.append((candidate,args))
 validcopy=False;validnotify=False
 for candidate,args in candidates:
  unconditional(candidate)
  good=args.get('src')=='previous.txt' and mode(args.get('mode'))==0o644 and not boolean(args.get('remote_src',False))
  validcopy=validcopy or good
  try: reload_handler(play,candidate); validnotify=validnotify or good
  except (AssertionError,ValueError,TypeError,KeyError): pass
 checks=[('first play hosts = fleet [DQ:hosts]',all(fleet(p) for p in data)),
 ('first play serial = 1 [DQ:serial]',one_at_a_time(play.get('serial'),play.get('hosts'))),
 ('first task block is a nonempty list [DQ:block]',isinstance(task.get('block'),list) and bool(task.get('block'))),
 ('first task rescue is a nonempty list [DQ:rescue]',isinstance(task.get('rescue'),list) and bool(task.get('rescue'))),
 ('first task always is a nonempty list [DQ:always]',isinstance(task.get('always'),list) and bool(task.get('always'))),
 ('first rescue copy = previous.txt to /srv/site/message mode 0644 [DQ:copy]',validcopy),
 ('first rescue notify = Reload banner [DQ:notify]',validnotify)]
except (OSError,ValueError,TypeError,KeyError,IndexError,AttributeError,AssertionError,yaml.YAMLError):
 checks=[(label,False) for label in ['first play hosts = fleet [DQ:hosts]','first play serial = 1 [DQ:serial]','first task block is a nonempty list [DQ:block]','first task rescue is a nonempty list [DQ:rescue]','first task always is a nonempty list [DQ:always]','first rescue copy = previous.txt to /srv/site/message mode 0644 [DQ:copy]','first rescue notify = Reload banner [DQ:notify]']]
for label,ok in checks:
 if not ok: print(label+': ✗')
sys.exit(not all(ok for _,ok in checks))
SCOPE
)
[ $? -eq 0 ] || dq_result_failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
test "$(curl -fsS --max-time 3 http://app1-${DQ_NAMESPACE#dq-}:8080)" = stable-63
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 HTTP / on port 8080 = stable-63 : ✗ [DQ:http_1]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app2-${DQ_NAMESPACE#dq-}:8080)" = stable-63
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 HTTP / on port 8080 = stable-63 : ✗ [DQ:http_2]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app3-${DQ_NAMESPACE#dq-}:8080)" = stable-63
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 HTTP / on port 8080 = stable-63 : ✗ [DQ:http_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || dq_result_failed=1
set -e
test "$dq_result_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
