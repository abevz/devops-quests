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
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" 'def same_dir($want): if type!="string" then false elif startswith("/") then false else (split("/") | map(select(.!="" and .!="."))) as $parts | ($parts | all(.!="..")) and ($parts | join("/")==$want) end; .spec.source.repoURL==$url and (.spec.source.path | same_dir("manifests")) and .spec.source.targetRevision=="main"' >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'Application Git source could not be verified: ✗ [DQ:git_source]' >&2
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
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
kubectl get application board -o json | jq -e '.spec.syncPolicy.automated.selfHeal==true and .spec.syncPolicy.automated.prune==true' >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'Application health and automation could not be verified: ✗ [DQ:git_health]' >&2
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
  printf '%s\n' 'Git workload rollout could not be verified: ✗ [DQ:git_rollout]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
test "$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080)" = north-68
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'Git workload response could not be verified: ✗ [DQ:git_http]' >&2
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
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository rev-parse origin/main)" = "$(cat release-commit)"
git -C repository merge-base --is-ancestor "$(cat /run/dq/facts/0/baseline-commit)" origin/main
test "$(git -C repository rev-parse origin/main)" != "$(cat /run/dq/facts/0/baseline-commit)"
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'Published descendant revision could not be verified: ✗ [DQ:git_descendant]' >&2
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
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY_PUBLICATION'
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
    assert agreement(desired,live)
    execute(['kubectl','rollout','status','deployment/board','--timeout=3s'])
    assert execute(['timeout','4s','kubectl','exec','--pod-running-timeout=2s','deployment/board','-c','worker','--','wget','-qO-','-T','3','http://board:8080']).rstrip(b'\n')==b'north-68'
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
DQ_LEGACY_PUBLICATION
)
[ $? -eq 0 ] || dq_result_failed=1
(
set -euo pipefail
source platform.env
python3 -I - <<'DQ_PUBLICATION'
import json
import posixpath
import subprocess
import time
from pathlib import Path
import yaml
from dq_check import workload_worker

deadline = time.monotonic() + 14
failed = False


def reject(marker):
    global failed
    failed = True
    print('Consumer publication is incomplete: ✗ [DQ:' + marker + ']')


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
    receipt = json.loads(Path('/run/dq/facts/0/publication-contract.json').read_text())
    snapshot = json.loads(execute(['kubectl', '--request-timeout=2s', 'get', 'application/board',
                                   'deployment/board', '-o', 'json']))
    observed = {item['kind']: item for item in snapshot['items']}
    app, live = observed['Application'], observed['Deployment']
    if app['metadata']['uid'] != receipt['applicationUID'] or live['metadata']['uid'] != receipt['deploymentUID']:
        reject('publication_identity')
    if (app['spec']['source'].get('repoURL') != receipt['repoURL']
            or workload_worker(live).get('image') != receipt['image']):
        reject('publication_source')
    revision = execute(['git', '-C', 'repository', 'rev-parse', 'origin/main']).decode().strip()
    if app.get('status', {}).get('sync', {}).get('revision') != revision:
        reject('publication_source')
    paths = execute(['git', '-C', 'repository', 'ls-tree', '-r', '--name-only', revision, '--', 'manifests']).decode().splitlines()
    desired = {}
    recurse = app['spec']['source'].get('directory', {}).get('recurse', False)
    for path in paths:
        if Path(path).suffix not in ('.yaml', '.yml', '.json') or (not recurse and len(path.split('/')) != 2):
            continue
        text = execute(['git', '-C', 'repository', 'show', revision + ':' + path]).decode()
        for root in yaml.safe_load_all(text):
            for item in documents(root):
                identity = item['kind'], item.get('metadata', {}).get('name')
                if identity in desired:
                    raise ValueError('duplicate manifest identity')
                desired[identity] = item
    declared = desired['Deployment', 'board']
    names = set()
    for volume in live['spec']['template']['spec'].get('volumes', []):
        if 'configMap' in volume:
            names.add(volume['configMap']['name'])
        names.update(item['configMap']['name'] for item in volume.get('projected', {}).get('sources', [])
                     if 'configMap' in item)
    if not names:
        reject('publication_projection')
    else:
        maps = {}
        for name in names:
            maps[name] = json.loads(execute(['kubectl', '--request-timeout=2s', 'get', 'configmap', name, '-o', 'json']))
            if desired['ConfigMap', name].get('data') != maps[name].get('data'):
                reject('publication_source')
        roots = execute(['kubectl', '--request-timeout=2s', 'exec', 'deployment/board', '-c', 'worker',
                         '--', 'sh', '-c', 'for pid in $(pidof httpd); do readlink "/proc/$pid/cwd"; done']).decode().splitlines()
        roots = set(roots)
        adopted = False
        declared_maps = {name: desired['ConfigMap', name] for name in names}
        for root in roots:
            files = {}
            for name in ('index.html', 'contract.json'):
                target = posixpath.join(root, name)
                actual = projection(live, target, maps)
                intended = projection(declared, target, declared_maps)
                if len(actual) != 1 or intended != actual:
                    break
                cm, key = actual[0]
                files[name] = maps[cm]['data'][key]
            else:
                body = json.loads(files['contract.json'])
                if (files['index.html'].rstrip('\n') == receipt['index'].rstrip('\n')
                        and all(body.get(k) == v for k, v in receipt['contract'].items())):
                    adopted = True
        if not adopted:
            reject('publication_projection')
    response = execute(['kubectl', '--request-timeout=2s', 'exec', 'deployment/board', '-c', 'worker',
                        '--', 'wget', '-qO-', '-T', '2', 'http://board:8080/contract.json'])
    payload = json.loads(response)
    if not isinstance(payload, dict) or not all(payload.get(k) == v for k, v in receipt['contract'].items()):
        reject('publication_http')
except subprocess.TimeoutExpired:
    reject('publication_budget')
except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, yaml.YAMLError):
    reject('publication_observation')
raise SystemExit(failed)
DQ_PUBLICATION
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
