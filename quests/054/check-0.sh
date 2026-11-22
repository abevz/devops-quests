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
dq_result_failed=0
set +e
(
set -euo pipefail
timeout --kill-after=1s 4s bash -euo pipefail <<'DQ_LEGACY_HANDOVER'
kubectl get application station -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null
DQ_LEGACY_HANDOVER
)
[ $? -eq 0 ] || dq_result_failed=1
(
set -euo pipefail
source platform.env
python3 -I - <<'DQ_HANDOVER'
import json
import subprocess
import time
from pathlib import Path
import yaml
from dq_check import workload_worker

deadline = time.monotonic() + 18
failed = False


def reject(marker):
    global failed
    failed = True
    print('Git handover is incomplete: ✗ [DQ:' + marker + ']')


def execute(args):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise subprocess.TimeoutExpired(args[0], 0)
    return subprocess.check_output(args, stderr=subprocess.DEVNULL, timeout=min(3, remaining))


def get(*resources):
    return json.loads(execute(['kubectl', '--request-timeout=2s', 'get', *resources, '-o', 'json']))


def same_dir(value, wanted):
    if not isinstance(value, str) or value.startswith('/'):
        return False
    parts = [p for p in value.split('/') if p not in ('', '.')]
    return '..' not in parts and '/'.join(parts) == wanted


def reader_fields(pod):
    return {
        'containers': [{k: c.get(k) for k in ('name', 'image', 'command', 'args', 'volumeMounts', 'securityContext')}
                       for c in pod['spec']['containers']],
        'volumes': pod['spec'].get('volumes', []),
        'securityContext': pod['spec'].get('securityContext'),
    }


def documents(value):
    if isinstance(value, dict):
        if value.get('kind') == 'List':
            for item in value.get('items', []):
                yield from documents(item)
        elif value.get('kind'):
            yield value


try:
    receipt = json.loads(Path('/run/dq/facts/0/handover-contract.json').read_text())
    original = receipt['original']
    resources = [kind + '/' + item['name'] for kind, item in original.items()]
    observed = get(*resources)
    live = {item['kind'].lower(): item for item in observed['items']}
    if any(live[kind]['metadata']['uid'] != item['uid'] for kind, item in original.items()):
        reject('handover_identity')
    old_map = live['configmap']
    if not old_map.get('immutable') or old_map.get('data') != original['configmap']['data']:
        reject('handover_retained')
    if reader_fields(live['pod']) != receipt['readerFields']:
        reject('handover_reader')
    current = execute(['kubectl', '--request-timeout=2s', 'exec', original['pod']['name'],
                       '--', 'wget', '-qO-', '-T', '2', 'http://127.0.0.1:8080'])
    if current != original['configmap']['data']['index.html'].encode():
        reject('handover_reader')
    app = live['application']
    spec = app['spec']
    source = spec.get('source', {})
    if (source.get('repoURL') != receipt['repoURL'] or source.get('targetRevision') != 'main'
            or not same_dir(source.get('path'), 'manifests')
            or spec.get('project') != receipt['project']
            or spec.get('destination') != receipt['destination']):
        reject('handover_source')
    for rule in spec.get('ignoreDifferences') or []:
        if (rule.get('group', '') in ('', '*', 'apps')
                and rule.get('kind', '*') in ('*', 'Deployment')
                and rule.get('name', original['deployment']['name']) == original['deployment']['name']
                and rule.get('namespace', receipt['namespace']) == receipt['namespace']
                and any(rule.get(key) for key in ('jsonPointers', 'jqPathExpressions', 'managedFieldsManagers'))):
            reject('handover_scope')
            break
    worker = workload_worker(live['deployment'])
    routes = [row for row in worker.get('env', []) if row.get('name') == 'ROUTE']
    if len(routes) != 1:
        raise ValueError('route binding')
    binding = routes[0].get('valueFrom', {}).get('configMapKeyRef', {})
    name, key = binding.get('name'), binding.get('key')
    if not name or not key or name == original['configmap']['name']:
        reject('handover_binding')
    else:
        new_map = get('configmap/' + name)
        if not new_map.get('immutable') or new_map.get('data', {}).get(key) != receipt['route']:
            reject('handover_binding')
        execute(['git', '-C', 'repository', 'fetch', '--quiet', receipt['repoURL'], 'main'])
        revision = execute(['git', '-C', 'repository', 'rev-parse', 'FETCH_HEAD']).decode().strip()
        execute(['git', '-C', 'repository', 'merge-base', '--is-ancestor', receipt['baselineCommit'], revision])
        if app.get('status', {}).get('sync', {}).get('revision') != revision:
            reject('handover_source')
        names = execute(['git', '-C', 'repository', 'ls-tree', '-r', '--name-only', revision, '--', 'manifests']).decode().splitlines()
        desired = {}
        recurse = source.get('directory', {}).get('recurse', False)
        for path in names:
            if Path(path).suffix not in ('.yaml', '.yml', '.json') or (not recurse and len(path.split('/')) != 2):
                continue
            text = execute(['git', '-C', 'repository', 'show', revision + ':' + path]).decode()
            for value in yaml.safe_load_all(text):
                for item in documents(value):
                    identity = item['kind'], item.get('metadata', {}).get('name')
                    if identity in desired:
                        raise ValueError('duplicate manifest identity')
                    desired[identity] = item
        declared = desired['Deployment', original['deployment']['name']]
        declared_routes = [row for row in workload_worker(declared).get('env', []) if row.get('name') == 'ROUTE']
        declared_map = desired['ConfigMap', name]
        if (declared_routes != routes or not declared_map.get('immutable')
                or declared_map.get('data') != new_map.get('data')):
            reject('handover_source')
        if not any(row.get('kind') == 'ConfigMap' and row.get('name') == name
                   and row.get('namespace') == receipt['namespace'] and row.get('status') == 'Synced'
                   for row in app.get('status', {}).get('resources', [])):
            reject('handover_source')
except subprocess.TimeoutExpired:
    reject('handover_budget')
except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, yaml.YAMLError):
    reject('handover_observation')
raise SystemExit(failed)
DQ_HANDOVER
)
[ $? -eq 0 ] || dq_result_failed=1
set -e
test "$dq_result_failed" -eq 0
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
test "$(kubectl exec deployment/relay -c worker -- printenv ROUTE)" = north
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The current route could not be verified: ✗ [DQ:handover_route]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
kubectl rollout status deployment/relay --timeout=3s >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The managed workload rollout could not be verified: ✗ [DQ:handover_rollout]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
