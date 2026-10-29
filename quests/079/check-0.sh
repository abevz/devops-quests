set -euo pipefail
cd ~/quest
failed=0
if ! python3 - <<'DQ_FLEET'
import sys
import yaml

errors = []

def expect(ok, label):
    if not ok:
        errors.append(label + ': ✗')


def mode(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    try:
        return int(str(value), 8)
    except (TypeError, ValueError):
        return None


try:
    plays = yaml.safe_load(open('rollout.yml'))
    if not isinstance(plays, list) or len(plays) != 1:
        raise ValueError('play count')
    play = plays[0]
    expect(play.get('hosts') == 'fleet', 'rollout.yml hosts = fleet')
    expect(set(play) <= {'name', 'hosts', 'gather_facts', 'handlers', 'tasks'}, 'rollout.yml play boundaries')
    tasks = play.get('tasks', [])
    expect(len(tasks) == 3, 'rollout.yml tasks = 3')
    found = {}
    for position, task in enumerate(tasks):
        expect(not any(k in task for k in ('changed_when', 'check_mode', 'when')), 'rollout.yml task execution controls')
        modules = [k for k in ('file', 'ansible.builtin.file', 'copy', 'ansible.builtin.copy') if k in task]
        expect(set(task) <= {'name', 'notify', 'file', 'ansible.builtin.file', 'copy', 'ansible.builtin.copy'}, 'rollout.yml task keys')
        if len(modules) != 1 or not isinstance(task[modules[0]], dict):
            errors.append('rollout.yml task module: ✗')
            continue
        key = modules[0].split('.')[-1]
        args = task[modules[0]]
        path = args.get('path') if key == 'file' else args.get('dest')
        if path in found:
            errors.append('rollout.yml duplicate destination: ✗')
            continue
        if path != '/srv/site/message':
            expect('notify' not in task, 'rollout.yml notify only banner')
        found[path] = (position, key, args, task)
    for path, kind, expected_mode, content in [('/srv/site/config', 'file', 0o755, None), ('/srv/site/message', 'copy', 0o644, 'north-79\n'), ('/srv/site/config/route', 'copy', 0o644, 'route=north\n')]:
        if path not in found:
            errors.append('rollout.yml ' + path + ': ✗')
            continue
        _, actual_kind, args, task = found[path]
        expect(actual_kind == kind, 'rollout.yml ' + path + ' module')
        expect(mode(args.get('mode')) == expected_mode, 'rollout.yml ' + path + ' mode')
        if kind == 'file':
            expect(args.get('state') == 'directory', 'rollout.yml directory state')
            expect(set(args) == {'path', 'state', 'mode'}, 'rollout.yml directory arguments')
        else:
            expect(args.get('content') == content, 'rollout.yml ' + path + ' content')
            expect(set(args) == {'dest', 'content', 'mode'}, 'rollout.yml ' + path + ' arguments')
        if path == '/srv/site/message':
            notify = task.get('notify')
            expect(notify == 'Reload banner' or notify == ['Reload banner'], 'rollout.yml notify Reload banner')
    if '/srv/site/config' in found and '/srv/site/config/route' in found:
        expect(found['/srv/site/config'][0] < found['/srv/site/config/route'][0], 'rollout.yml directory before route')
    handlers = play.get('handlers', [])
    expect(len(handlers) == 1 and handlers[0].get('name') == 'Reload banner', 'rollout.yml handler Reload banner')
    if len(handlers) == 1:
        handler = handlers[0]
        command = handler.get('ansible.builtin.command', handler.get('command'))
        expect(set(handler) <= {'name', 'command', 'ansible.builtin.command'} and sum(k in handler for k in ('command', 'ansible.builtin.command')) == 1 and command == 'dq-service reload', 'rollout.yml handler dq-service reload')
except (OSError, TypeError, ValueError, KeyError, yaml.YAMLError):
    errors.append('rollout.yml: ✗')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
DQ_FLEET
then
  failed=1
fi
if ! test -s repair.log; then
  printf '%s\n' 'repair.log ≠ empty: ✗'
  failed=1
fi
for i in 1 2 3; do
  if ! grep -Eq "^app$i[[:space:]]+:.*changed=0.*unreachable=0.*failed=0" second.log 2>/dev/null; then
    printf '%s\n' "second.log app$i changed=0 unreachable=0 failed=0: ✗"
    failed=1
  fi
  remote_output=$(mktemp)
  if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@app$i-${DQ_NAMESPACE#dq-}" "HOST=app$i bash -s" > "$remote_output" 2>/dev/null <<'DQ_REMOTE'
set -u
failed=0
if ! test "$(stat -c %a /srv/site/config 2>/dev/null)" = 755; then printf '%s\n' "$HOST /srv/site/config mode = 0755: ✗"; failed=1; fi
if ! test "$(stat -c %a /srv/site/message 2>/dev/null)" = 644; then printf '%s\n' "$HOST /srv/site/message mode = 0644: ✗"; failed=1; fi
if ! test "$(cat /srv/site/message 2>/dev/null)" = north-79; then printf '%s\n' "$HOST /srv/site/message = north-79: ✗"; failed=1; fi
if ! test "$(stat -c %a /srv/site/config/route 2>/dev/null)" = 644; then printf '%s\n' "$HOST /srv/site/config/route mode = 0644: ✗"; failed=1; fi
if ! test "$(cat /srv/site/config/route 2>/dev/null)" = route=north; then printf '%s\n' "$HOST /srv/site/config/route = route=north: ✗"; failed=1; fi
exit "$failed"
DQ_REMOTE
  then
    if ! test -s "$remote_output"; then printf '%s\n' "app$i SSH: ✗"; fi
    cat "$remote_output"
    failed=1
  fi
  rm -f "$remote_output"
  if ! test "$(curl -fsS --max-time 3 "http://app$i-${DQ_NAMESPACE#dq-}:8080" 2>/dev/null)" = north-79; then
    printf '%s\n' "app$i:8080 = north-79: ✗"
    failed=1
  fi
done
exit "$failed"
