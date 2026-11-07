set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
test "$(cat fleet.txt)" = "$(printf 'app1
app2
app3')"
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(stat -c %a fleet.txt)" = 644
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test ! -e /srv/site/fleet.txt'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'No /srv/site/fleet.txt is present on app1 : ✗ [DQ:absent_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test ! -e /srv/site/fleet.txt'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'No /srv/site/fleet.txt is present on app2 : ✗ [DQ:absent_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test ! -e /srv/site/fleet.txt'
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'No /srv/site/fleet.txt is present on app3 : ✗ [DQ:absent_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
python3 -I - <<'DQ_DELEGATION'
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
    assert all(not play.get('roles') for play in data), 'Uninspected roles cannot certify one workstation writer'
    return data

def flat(play):
    context = {key: play[key] for key in ('no_log', 'check_mode', 'tags', 'vars', 'delegate_to', 'run_once', 'when', 'collections') if key in play}
    return list(tasks(play.get('pre_tasks', []) + play.get('tasks', []) + play.get('post_tasks', []), context))

def unconditional(task):
    assert not any(task.get(key) not in (None, [], True, 'true', 'True') for key in ('when',))
    assert not any(key in task for key in ('loop', 'with_items', 'until', 'ignore_errors', 'ignore_unreachable', 'failed_when'))

from pathlib import Path
import jinja2
from ansible.plugins.filter.core import FilterModule

environment=jinja2.Environment(undefined=jinja2.StrictUndefined)
environment.filters.update(FilterModule().filters())
def report_context(items, conditional=False):
 for task in items or []:
  assert not task.get('module_defaults'), 'Opaque module defaults cannot redirect the report writer'
  if 'block' in task:
   yield from report_context(task['block'],conditional)
   yield from report_context(task.get('rescue',[]),True)
   yield from report_context(task.get('always',[]),conditional)
  else:yield conditional

writers=[]
for play in plays():
 assert not play.get('vars_files') and not play.get('vars_prompt') and not play.get('module_defaults'), 'The report needs explicit, stable input bindings'
 ordered=flat(play)
 contexts=list(report_context(play.get('pre_tasks',[])+play.get('tasks',[])+play.get('post_tasks',[])))
 assert len(ordered)==len(contexts)
 for position,task in enumerate(ordered):
  module,args=action(task)
  assert not names(task.get('notify')), 'Only the single visible task may write the report'
  if module in ('stat','debug','assert','fail'):
   unconditional(task);continue
  assert module in ('copy','template'), 'Unanalysed command effects cannot certify a dynamic report'
  assert args.get('dest') in ('fleet.txt','{{ playbook_dir }}/fleet.txt',str(Path.cwd()/'fleet.txt')), 'Only the supplied report write is certified'
  assert not contexts[position], 'The report must not depend on the rescue branch running'
  tags=names(task.get('tags'))
  assert not any(mark in tag for tag in tags for mark in ('{{','{%','{#'))
  assert 'never' not in tags or 'always' in tags, 'The report writer must run in the default selection'
  unconditional(task)
  variables=task.get('vars',{})
  delegate=task.get('delegate_to')
  if isinstance(delegate,str):delegate=environment.from_string(delegate).render(variables)
  assert 'local_action' in task or delegate in ('localhost','127.0.0.1','::1'), 'Delegate the report writer to the workstation'
  assert boolean(task.get('run_once')) is True, 'Only one report writer is permitted'
  if module=='copy': content=args.get('content')
  else:
   source=Path(args['src'])
   if not source.is_file():source=Path('templates')/source
   content=source.read_text()
  assert isinstance(content,str)
  # Different sizes and names reject a hard-coded sample without fixing one Jinja representation.
  for hosts in (['probe-b','probe-a'],['delta','alpha','charlie','bravo'],['solo']):
   context={**variables,'groups':{'fleet':hosts,'all':hosts},'ansible_play_hosts_all':hosts,'ansible_play_hosts':hosts,'play_hosts':hosts,'hostvars':{host:{} for host in hosts},'inventory_hostname':hosts[0]}
   for _ in range(len(variables)+1):
    for name,value in variables.items():
     if isinstance(value,str):context[name]=environment.from_string(value).render(context)
   rendered=environment.from_string(content).render(context)
   assert rendered.splitlines()==sorted(hosts), 'Derive the complete sorted current fleet membership'
  writers.append(task)
assert len(writers)==1, 'Keep one local report writer'
# Validate the supported declaration with the same pinned Ansible parser.
import subprocess
subprocess.run(['ansible-playbook','--syntax-check','rollout.yml'],check=True,capture_output=True,text=True,timeout=5)
DQ_DELEGATION
)
[ $? -eq 0 ] || failed=1
exit "$failed"
