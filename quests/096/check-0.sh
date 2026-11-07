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
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_result_failed=0
set +e
(
set -e
python3 -I - <<'VERIFY'
import shlex
import yaml
from pathlib import Path

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
    assert all(not play.get('roles') for play in data), 'Role effects are outside the certified task workflow'
    return data

def flat(play):
    context = {key: play[key] for key in ('no_log', 'check_mode', 'tags', 'vars', 'delegate_to', 'run_once', 'when', 'collections') if key in play}
    return list(tasks(play.get('pre_tasks', []) + play.get('tasks', []) + play.get('post_tasks', []), context))

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

restores=[]
for play in plays():
 for task in flat(play):
  module,args=action(task)
  if module!='unarchive':continue
  assert one_at_a_time(play.get('serial'),play.get('hosts')), 'Restore one managed host at a time'
  unconditional(task)
  assert args.get('src') in ('recovery.tar','{{ playbook_dir }}/recovery.tar',str(Path.cwd() / 'recovery.tar'))
  assert args.get('dest')=='/srv/site' and str(args.get('owner')) in ('root','0') and str(args.get('group')) in ('root','0')
  assert mode(args.get('mode'))==0o644 and boolean(args.get('remote_src',False)) is False
  reload_handler(play,task);restores.append(task)
assert restores, 'Restore the trusted archive and reload the service'
VERIFY
)
[ $? -eq 0 ] || dq_result_failed=1
(
set -e
python3 -I - <<'VERIFY'
import shlex
import yaml
from pathlib import Path

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
    assert all(not play.get('roles') for play in data), 'Role effects are outside the certified task workflow'
    return data

def flat(play):
    context = {key: play[key] for key in ('no_log', 'check_mode', 'tags', 'vars', 'delegate_to', 'run_once', 'when', 'collections') if key in play}
    return list(tasks(play.get('pre_tasks', []) + play.get('tasks', []) + play.get('post_tasks', []), context))

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

restores=[]
for play in plays():
 for task in flat(play):
  module,args=action(task)
  if module!='unarchive':continue
  assert one_at_a_time(play.get('serial'),play.get('hosts')), 'Restore one managed host at a time'
  unconditional(task)
  assert args.get('src') in ('recovery.tar','{{ playbook_dir }}/recovery.tar',str(Path.cwd() / 'recovery.tar'))
  assert args.get('dest')=='/srv/site' and str(args.get('owner')) in ('root','0') and str(args.get('group')) in ('root','0')
  assert mode(args.get('mode'))==0o644 and boolean(args.get('remote_src',False)) is False
  reload_handler(play,task);restores.append(task)
assert restores, 'Restore the trusted archive and reload the service'
VERIFY
)
[ $? -eq 0 ] || dq_result_failed=1
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
