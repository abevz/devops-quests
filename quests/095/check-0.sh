set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set +e
(
set -e
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository rev-parse origin/main)" = "$(cat release-commit)"
faulty=$(cat /run/dq/facts/0/faulty-commit)
test "$(cat release-commit)" != "$faulty"
git -C repository merge-base --is-ancestor "$faulty" origin/main
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The forward recovery head could not be verified: ✗ [DQ:rollback_head]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg url "$GIT_URL" 'def same_dir($want): if type!="string" then false elif startswith("/") then false else (split("/") | map(select(.!="" and .!="."))) as $parts | ($parts | all(.!="..")) and ($parts | join("/")==$want) end; .spec.source.repoURL==$url and (.spec.source.path | same_dir("manifests")) and .spec.source.targetRevision=="main"' >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The retained Git source could not be verified: ✗ [DQ:rollback_source]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.spec.syncPolicy.automated.selfHeal==true and .spec.syncPolicy.automated.prune==true and .status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The synchronized recovery revision could not be verified: ✗ [DQ:rollback_sync]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The current producer rollout could not be verified: ✗ [DQ:rollback_rollout]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- wget -qO- -T 3 http://board:8080)" = north-95
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The actual producer response could not be verified: ✗ [DQ:rollback_http]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
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
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY_ROLLBACK_ADOPTION'
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
python3 -I - <<'DQ_GIT_HEALTH'
import json,re,subprocess,sys,yaml
from pathlib import Path
from decimal import Decimal

def execute(args):return subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=4)
def deployment(text):
    found=[]
    def visit(value,depth=0):
        if depth>64:raise ValueError('manifest nesting')
        if isinstance(value,list):
            for entry in value:visit(entry,depth+1)
        elif isinstance(value,dict):
            if value.get('kind')=='List':visit(value.get('items',[]),depth+1)
            elif value.get('kind')=='Deployment' and value.get('metadata',{}).get('name')=='board':found.append(value)
    for value in yaml.safe_load_all(text):visit(value)
    if len(found)!=1:raise ValueError('board Deployment identity')
    return found[0]
from dq_check import workload_worker as _dq_worker

def worker(document):
    return _dq_worker(document, error="application worker identity")
from dq_check import quantity as _dq_quantity

def quantity(value):
    return _dq_quantity(value, dialect='unicode_finite')

from dq_check import resource_subset as subset


from dq_check import health_probe as probe

from dq_check import env_values as env

from dq_check import workload_agreement as agreement

from dq_check import workload_safety as safety

try:
    desired=deployment(execute(['git','-C','repository','show','origin/main:manifests/board.yaml']))
    live=json.loads(execute(['kubectl','get','deployment','board','-o','json']))
    healthy=Path('/run/dq/facts/0/healthy-commit').read_text().strip()
    reference=deployment(execute(['git','-C','repository','show',healthy+':manifests/board.yaml']))
    assert subset(reference,desired,ignore_behavior=True) and subset(reference,live,ignore_behavior=True)
    assert safety(reference,desired) and safety(reference,live)
    for field in ('livenessProbe','startupProbe'):
        assert probe(worker(reference),field)==probe(worker(desired),field)==probe(worker(live),field)
    assert agreement(desired,live)
    execute(['kubectl','rollout','status','deployment/board','--timeout=3s'])
    assert execute(['timeout','4s','kubectl','exec','--pod-running-timeout=2s','deployment/board','-c','worker','--','wget','-qO-','-T','3','http://board:8080']).rstrip(b'\n')==b'north-95'
except Exception:
    sys.exit(1)
DQ_GIT_HEALTH
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_5]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
DQ_LEGACY_ROLLBACK_ADOPTION
)
[ $? -eq 0 ] || dq_result_failed=1
(
set -euo pipefail
source platform.env
python3 -I - <<'DQ_ROLLBACK_ADOPTION'
import json
import posixpath
import subprocess
import time
from pathlib import Path
import yaml
from dq_check import workload_worker, current_pods, ready_image, pod_worker

deadline = time.monotonic() + 14
failed = False


def reject(marker):
    global failed
    failed = True
    print('Rollback propagation is incomplete: ✗ [DQ:' + marker + ']')


def execute(args):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise subprocess.TimeoutExpired(args[0], 0)
    return subprocess.check_output(args, stderr=subprocess.DEVNULL, timeout=min(3, remaining))


def documents(value):
    if isinstance(value, dict):
        if value.get('kind') == 'List':
            for item in value.get('items', []):
                yield from documents(item)
        elif value.get('kind'):
            yield value


def same_dir(value, wanted):
    if not isinstance(value, str) or value.startswith('/'):
        return False
    parts = [part for part in value.split('/') if part not in ('', '.')]
    return '..' not in parts and '/'.join(parts) == wanted


def projection(document, filename, maps):
    worker = workload_worker(document)
    result = []
    volumes = {v['name']: v for v in document['spec']['template']['spec'].get('volumes', [])}
    for mount in worker.get('volumeMounts', []):
        base = mount['mountPath'].rstrip('/') or '/'
        if 'subPath' in mount:
            if filename != mount['mountPath']:
                continue
        elif filename != base and not filename.startswith(base.rstrip('/') + '/'):
            continue
        volume = volumes[mount['name']]
        sources = [volume['configMap']] if 'configMap' in volume else [
            item['configMap'] for item in volume.get('projected', {}).get('sources', []) if 'configMap' in item]
        for source in sources:
            name = source['name']
            data = maps[name].get('data', {})
            items = source.get('items', [{'key': key, 'path': key} for key in data])
            for item in items:
                if 'subPath' in mount:
                    path = mount['mountPath'] if item['path'] == mount['subPath'] else None
                else:
                    path = posixpath.normpath(posixpath.join(mount['mountPath'], item['path']))
                if path == filename:
                    result.append((name, item['key']))
    return result


try:
    receipt = json.loads(Path('/run/dq/facts/0/rollback-contract.json').read_text())
    resources = list(receipt['originalIdentities'])
    snapshot = json.loads(execute(['kubectl', '--request-timeout=2s', 'get', *resources, '-o', 'json']))
    observed = {(item['kind'].lower(), item['metadata']['name']): item for item in snapshot['items']}
    for name in ('board', 'reader-a', 'reader-b'):
        suffix = 'board' if name == 'board' else name[-1]
        if any(observed[kind, name]['metadata']['uid'] != receipt['originalIdentities'][kind + '/' + name]
               for kind in ('application', 'deployment')):
            reject('rollback_identity_' + suffix)
    revision = execute(['git', '-C', 'repository', 'rev-parse', 'origin/main']).decode().strip()
    execute(['git', '-C', 'repository', 'merge-base', '--is-ancestor', receipt['baselineCommit'], revision])
    if revision == receipt['baselineCommit']:
        reject('rollback_history')
    parent = observed['application', 'board']
    if parent['spec']['source'].get('repoURL') != receipt['repoURL']:
        reject('rollback_history')
    names = execute(['git', '-C', 'repository', 'ls-tree', '-r', '--name-only', revision, '--', 'readers']).decode().splitlines()
    desired = {}
    for path in names:
        if Path(path).suffix not in ('.yaml', '.yml', '.json'):
            continue
        text = execute(['git', '-C', 'repository', 'show', revision + ':' + path]).decode()
        for root in yaml.safe_load_all(text):
            for item in documents(root):
                identity = item['kind'], item.get('metadata', {}).get('name')
                if identity in desired:
                    raise ValueError('duplicate consumer manifest identity')
                desired[identity] = item
    ownership = json.loads(execute(['kubectl', '--request-timeout=2s', 'get', 'replicasets,pods', '-o', 'json']))
    replicasets = {'items': [item for item in ownership['items'] if item['kind'] == 'ReplicaSet']}
    pods = {'items': [item for item in ownership['items'] if item['kind'] == 'Pod']}
    map_names = set()
    for profile in receipt['consumers']:
        live = observed['deployment', profile['name']]
        for volume in live['spec']['template']['spec'].get('volumes', []):
            if 'configMap' in volume:
                map_names.add(volume['configMap']['name'])
            map_names.update(item['configMap']['name'] for item in volume.get('projected', {}).get('sources', [])
                             if 'configMap' in item)
    if not map_names:
        raise ValueError('consumer publication sources')
    maps_snapshot = json.loads(execute(['kubectl', '--request-timeout=2s', 'get',
                                        *['configmap/' + name for name in sorted(map_names)], '-o', 'json']))
    maps_items = maps_snapshot.get('items', [maps_snapshot])
    maps = {item['metadata']['name']: item for item in maps_items}
    for profile in receipt['consumers']:
        name, lane = profile['name'], profile['lane']
        app, live = observed['application', name], observed['deployment', name]
        source = app['spec'].get('source', {})
        if (source.get('repoURL') != receipt['repoURL'] or not same_dir(source.get('path'), profile['path'])
                or source.get('targetRevision', '').lower() != revision
                or app['spec'].get('project') != profile['project']
                or app['spec'].get('destination') != profile['destination']
                or app.get('status', {}).get('sync', {}).get('revision') != revision
                or app.get('status', {}).get('sync', {}).get('status') != 'Synced'
                or app.get('status', {}).get('health', {}).get('status') != 'Healthy'):
            reject('rollback_source_' + lane)
        worker = workload_worker(live)
        declared = desired['Deployment', name]
        expected = profile['program']
        if any(worker.get(key) != expected.get(key) or workload_worker(declared).get(key) != expected.get(key)
               for key in ('image', 'command', 'args')):
            reject('rollback_delivery_' + lane)
        count = live['spec'].get('replicas', 1)
        status = live.get('status', {})
        owned = current_pods(live, replicasets, pods)
        if (count < 1 or status.get('observedGeneration', 0) < live['metadata']['generation']
                or status.get('updatedReplicas', 0) != count or status.get('readyReplicas', 0) != count
                or status.get('unavailableReplicas', 0) != 0 or len(owned) != count
                or any(not ready_image(pod, expected['image']) for pod in owned)):
            reject('rollback_delivery_' + lane)
        target = posixpath.join(profile['documentRoot'], 'index.html')
        bindings = projection(live, target, maps)
        declared_maps = {key[1]: value for key, value in desired.items() if key[0] == 'ConfigMap'}
        if len(bindings) != 1 or projection(declared, target, declared_maps) != bindings:
            reject('rollback_delivery_' + lane)
        else:
            cm, key = bindings[0]
            body = json.loads(maps[cm]['data'][key])
            if (not isinstance(body, dict) or not all(body.get(k) == v for k, v in receipt['publication'].items())
                    or declared_maps[cm].get('data') != maps[cm].get('data')):
                reject('rollback_delivery_' + lane)
        for pod in owned:
            if any(pod_worker(pod).get(key) != expected.get(key) for key in ('image', 'command', 'args')):
                reject('rollback_delivery_' + lane)
            actual_pod = {'spec': {'template': {'spec': pod['spec']}}}
            if projection(actual_pod, target, maps) != bindings:
                reject('rollback_delivery_' + lane)
            body = json.loads(execute(['kubectl', '--request-timeout=2s', 'exec', pod['metadata']['name'],
                                       '-c', 'worker', '--', 'wget', '-qO-', '-T', '2', 'http://127.0.0.1:8080']))
            if not isinstance(body, dict) or not all(body.get(k) == v for k, v in receipt['publication'].items()):
                reject('rollback_http_' + lane)
        if owned:
            body = json.loads(execute(['kubectl', '--request-timeout=2s', 'exec', owned[0]['metadata']['name'],
                                       '-c', 'worker', '--', 'wget', '-qO-', '-T', '2', 'http://' + name + ':8080']))
            if not isinstance(body, dict) or not all(body.get(k) == v for k, v in receipt['publication'].items()):
                reject('rollback_http_' + lane)
except subprocess.TimeoutExpired:
    reject('rollback_budget')
except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, yaml.YAMLError):
    reject('rollback_observation')
raise SystemExit(failed)
DQ_ROLLBACK_ADOPTION
)
[ $? -eq 0 ] || dq_result_failed=1
set -e
test "$dq_result_failed" -eq 0
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_5]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
