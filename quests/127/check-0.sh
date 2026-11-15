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
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY_NETWORK_127_0'
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
set -euo pipefail
cd ~/quest
failed=0
selector_ok() {
  python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 /dev/fd/6 3<<<"$1" 4<<<"$pods" 5<<<"$2" 6<<<"$3" <<'DQ_SELECTOR'
import sys

from dq_check import read_argument as _dq_read_argument

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys
try:
    service,pods=json.loads(sys.argv[1]),json.loads(sys.argv[2])['items'];key,value=sys.argv[3:5]
    selector=service['spec']['selector']
    intended=[p for p in pods if p['metadata'].get('labels',{}).get(key)==value and not p['metadata'].get('deletionTimestamp')]
    from dq_check import selector_matches as _dq_matches

    def matches(p):
        return all(_dq_matches(p["metadata"].get("labels", {}), {"matchLabels": {k: v}}, dialect="pdb") for k, v in selector.items())
    ok=isinstance(selector,dict) and selector.get(key)==value and bool(intended) and all(matches(p) for p in intended) and all(not matches(p) or p['metadata'].get('labels',{}).get(key)==value for p in pods)
except (ValueError,KeyError,TypeError,AttributeError):ok=False
sys.exit(not ok)
DQ_SELECTOR
}
pods=$(timeout 2s kubectl get pods -o json 2>/dev/null || true)
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
service=$(timeout 2s kubectl get service board -o json 2>/dev/null || true)
if ! python3 -I - /dev/fd/3 /dev/fd/4 3<<<"$service" 4<<<"$pods" <<'DQ_METRICS_PORT'
import sys

from dq_check import read_argument as _dq_read_argument

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys
try:
    service=json.loads(sys.argv[1]);pods=json.loads(sys.argv[2])['items']
    ports=[p for p in service['spec']['ports'] if p.get('name')=='http']
    port=ports[0] if len(ports)==1 else {}
    published=port.get('port')==8080 and port.get('protocol','TCP')=='TCP'
    value=port.get('targetPort',port.get('port'))
    if type(value) is int:target=value==8080
    elif isinstance(value,str):
        targets=[p for p in pods if p.get('metadata',{}).get('labels',{}).get('app')=='board' and not p.get('metadata',{}).get('deletionTimestamp')]
        target=bool(targets)
        for pod in targets:
            found=[p['containerPort'] for c in pod['spec']['containers'] for p in c.get('ports',[]) if p.get('name')==value and p.get('protocol','TCP')=='TCP']
            target=target and found==[8080]
    else:target=False
except (ValueError,KeyError,TypeError,AttributeError):published=target=False
if not published:print('service board HTTP port = 8080: ✗ [DQ:port]')
if not target:print('service board HTTP target reaches application listener: ✗ [DQ:target_port]')
sys.exit(not (published and target))
DQ_METRICS_PORT
then failed=1; fi
if ! selector_ok "$service" app board; then printf '%s\n' 'service selector retains only the supplied board workload: ✗ [DQ:selector]'; failed=1; fi
exit "$failed"
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
DQ_LEGACY_NETWORK_127_0
python3 -I - <<'DQ_OBSERVER_INPUTS'
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from dq_check import current_pods, pod_worker, selector_matches, workload_worker

failed = False
deadline = time.monotonic() + 10
namespace = os.environ['DQ_NAMESPACE']


def require(value, marker):
    global failed
    if not value:
        print('Network condition is unmet: ✗ [DQ:' + marker + ']')
        failed = True


def command(arguments):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError('Observation budget exhausted')
    result = subprocess.run(arguments, capture_output=True, text=True,
                            timeout=min(6, remaining))
    if result.returncode:
        raise ValueError('Observation unavailable')
    return result.stdout


def get(kind, name=None):
    args = ['kubectl', 'get', kind]
    if name is not None:
        args.append(name)
    return json.loads(command(args + ['-o', 'json']))


def resource(items, name):
    matches = [item for item in items if item.get('metadata', {}).get('name') == name]
    if len(matches) != 1:
        raise ValueError('Resource identity')
    return matches[0]


def same_image(actual, expected):
    digest = expected.partition('@')[2]
    return actual == expected or (bool(digest) and isinstance(actual, str)
                                  and actual.partition('@')[2] == digest)


def preserved(facts, deployments, replicasets=None, pods=None):
    for name, identity in facts['deployments'].items():
        deployment = resource(deployments['items'], name)
        if deployment['metadata']['uid'] != identity['uid'] or not same_image(workload_worker(deployment).get('image'), identity['image']):
            return False
        if replicasets is not None and pods is not None:
            if any(not same_image(pod_worker(pod).get('image'), identity['image'])
                   for pod in current_pods(deployment, replicasets, pods)):
                return False
    return True


def ready(pod):
    return pod.get('status', {}).get('phase') == 'Running' and any(
        condition.get('type') == 'Ready' and condition.get('status') == 'True'
        for condition in pod.get('status', {}).get('conditions', []))
import base64
from decimal import Decimal, InvalidOperation
import hashlib
import re
import shlex

facts = json.loads(Path('/run/dq/facts/0/observer-identities.json').read_text())
contract = facts['contract']


def consumers(deployments, replicasets, pods):
    result = []
    for role in contract['consumers']:
        name = role['deployment']
        deployment = resource(deployments['items'], name)
        identity = facts['deployments'][name]
        if deployment['metadata']['uid'] != identity['uid']:
            raise ValueError('Consumer identity')
        active = current_pods(deployment, replicasets, pods)
        if len(active) != 1 or not ready(active[0]) or not same_image(pod_worker(active[0]).get('image'), identity['image']):
            raise ValueError('Current consumer unavailable')
        result.append((role, deployment, active[0]))
    return result


def template_environment(template, worker, configmaps):
    values = {}
    secret_cache = {}

    def source(kind, reference):
        name = reference['name']
        try:
            if kind == 'configMap':
                return resource(configmaps['items'], name).get('data', {})
            if name not in secret_cache:
                secret_cache[name] = get('secret', name)
            return {key: base64.b64decode(value, validate=True).decode()
                    for key, value in secret_cache[name].get('data', {}).items()}
        except (KeyError, ValueError):
            if reference.get('optional'):
                return {}
            raise

    for entry in worker.get('envFrom', []):
        kind = 'configMap' if 'configMapRef' in entry else 'secret'
        reference = entry.get('configMapRef') or entry.get('secretRef')
        if reference is None:
            raise ValueError('Environment source')
        prefix = entry.get('prefix', '')
        values.update({prefix + key: value for key, value in source(kind, reference).items()})
    for entry in worker.get('env', []):
        name = entry['name']
        if 'valueFrom' not in entry:
            value = entry.get('value', '').replace('$$', chr(0))
            value = re.sub(r'\$\(([A-Za-z_][A-Za-z_0-9]*)\)',
                           lambda match: values.get(match.group(1), match.group(0)) or match.group(0), value)
            values[name] = value.replace(chr(0), '$')
            continue
        reference = entry['valueFrom']
        key_ref = reference.get('configMapKeyRef') or reference.get('secretKeyRef')
        if key_ref is not None:
            kind = 'configMap' if 'configMapKeyRef' in reference else 'secret'
            data = source(kind, key_ref)
            if key_ref['key'] in data:
                values[name] = data[key_ref['key']]
            elif not key_ref.get('optional'):
                raise ValueError('Environment key')
        elif 'fieldRef' in reference:
            path = reference['fieldRef'].get('fieldPath', '')
            match = re.fullmatch(r"metadata\.(labels|annotations)\['([^']+)'\]", path)
            values[name] = template.get('metadata', {}).get(match.group(1), {}).get(match.group(2)) if match else None
        else:
            values[name] = None
    return values
try:
    deployments = get('deployments')
    replicasets = get('replicasets')
    pods = get('pods')
    configmaps = get('configmaps')
    service = get('service', 'board')
    require(service['metadata']['uid'] == facts['serviceUID']
            and preserved(facts, deployments, replicasets, pods), 'observer_identity')
    metrics = resource(configmaps['items'], 'board-metrics')
    code = resource(configmaps['items'], contract['programConfigMap'])
    require(metrics['metadata']['uid'] == facts['metricsUID']
            and code['metadata']['uid'] == facts['programUID']
            and hashlib.sha256(code['data'][contract['programKey']].encode()).hexdigest() == facts['programHash'],
            'observer_code')
    for role, deployment, pod in consumers(deployments, replicasets, pods):
        try:
            expected = dict(facts['intent'], OPERATION=role['operation'])
            worker = workload_worker(deployment)
            values = template_environment(deployment['spec']['template'], worker, configmaps)
            launch = worker.get('command', [])
            launches = (['sh', contract['programPath']], ['/bin/sh', contract['programPath']])
            require(launch in launches and pod_worker(pod).get('command', []) in launches, 'observer_code')
            require(all(values.get(key) == value for key, value in expected.items()), 'observer_template')
            observation = command(['kubectl', 'exec', pod['metadata']['name'], '-c', 'worker', '--',
                                   'sh', '-c', 'printf "%s\\n" "$PROMETHEUS_URL" "$METRIC" "$ROUTE" "$JOB" "$OPERATION"; sha256sum ' + shlex.quote(contract['programPath'])]).splitlines()
            require(len(observation) == 6
                    and observation[:5] == [expected[key] for key in ('PROMETHEUS_URL', 'METRIC', 'ROUTE', 'JOB', 'OPERATION')],
                    'observer_current')
            require(len(observation) == 6 and observation[5].split()[0] == facts['programHash'], 'observer_code')
        except (KeyError, ValueError, TypeError, AttributeError, IndexError, OSError, subprocess.SubprocessError):
            require(False, 'observer_current')
except (KeyError, ValueError, TypeError, AttributeError, OSError, subprocess.SubprocessError):
    require(False, 'observer_identity')
sys.exit(failed)
DQ_OBSERVER_INPUTS
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
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
timeout --kill-after=1s 9s bash -euo pipefail <<'DQ_LEGACY_NETWORK_127_1'
set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
url=$(jq -r '.url // ""' /run/dq/facts/0/prometheus-target.json 2>/dev/null || true)
up=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=up%7Bjob%3D%22board%22%7D" 2>/dev/null || true)
targets=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "$url/api/v1/targets?state=active" 2>/dev/null || true)
query=up
  case "$query" in up) doc=$up; expected=1;; sum) doc=$sum; expected=7;; count) doc=$count; expected=2;; esac
  check "${query}_status" "$query query status = success" '.status=="success"' "$doc"
  check "${query}_count" "$query query returns one result" '(.data.result|length)==1' "$doc"
  if ! jq -e --arg expected "$expected" '.data.result[0].value[1]==$expected' <<<"$doc" >/dev/null 2>&1; then printf '%s\n' "$query query value = $expected: ✗ [DQ:${query}_value]"; failed=1; fi
check target_health 'one active board target is up with empty lastError' 'any(.data.activeTargets[]?;.labels.job=="board" and .health=="up" and .lastError=="")' "$targets"
exit "$failed"

DQ_LEGACY_NETWORK_127_1
python3 -I - <<'DQ_OBSERVER_DELIVERY'
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from dq_check import current_pods, pod_worker, selector_matches, workload_worker

failed = False
deadline = time.monotonic() + 10
namespace = os.environ['DQ_NAMESPACE']


def require(value, marker):
    global failed
    if not value:
        print('Network condition is unmet: ✗ [DQ:' + marker + ']')
        failed = True


def command(arguments):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError('Observation budget exhausted')
    result = subprocess.run(arguments, capture_output=True, text=True,
                            timeout=min(6, remaining))
    if result.returncode:
        raise ValueError('Observation unavailable')
    return result.stdout


def get(kind, name=None):
    args = ['kubectl', 'get', kind]
    if name is not None:
        args.append(name)
    return json.loads(command(args + ['-o', 'json']))


def resource(items, name):
    matches = [item for item in items if item.get('metadata', {}).get('name') == name]
    if len(matches) != 1:
        raise ValueError('Resource identity')
    return matches[0]


def same_image(actual, expected):
    digest = expected.partition('@')[2]
    return actual == expected or (bool(digest) and isinstance(actual, str)
                                  and actual.partition('@')[2] == digest)


def preserved(facts, deployments, replicasets=None, pods=None):
    for name, identity in facts['deployments'].items():
        deployment = resource(deployments['items'], name)
        if deployment['metadata']['uid'] != identity['uid'] or not same_image(workload_worker(deployment).get('image'), identity['image']):
            return False
        if replicasets is not None and pods is not None:
            if any(not same_image(pod_worker(pod).get('image'), identity['image'])
                   for pod in current_pods(deployment, replicasets, pods)):
                return False
    return True


def ready(pod):
    return pod.get('status', {}).get('phase') == 'Running' and any(
        condition.get('type') == 'Ready' and condition.get('status') == 'True'
        for condition in pod.get('status', {}).get('conditions', []))
import base64
from decimal import Decimal, InvalidOperation
import hashlib
import re
import shlex

facts = json.loads(Path('/run/dq/facts/0/observer-identities.json').read_text())
contract = facts['contract']


def consumers(deployments, replicasets, pods):
    result = []
    for role in contract['consumers']:
        name = role['deployment']
        deployment = resource(deployments['items'], name)
        identity = facts['deployments'][name]
        if deployment['metadata']['uid'] != identity['uid']:
            raise ValueError('Consumer identity')
        active = current_pods(deployment, replicasets, pods)
        if len(active) != 1 or not ready(active[0]) or not same_image(pod_worker(active[0]).get('image'), identity['image']):
            raise ValueError('Current consumer unavailable')
        result.append((role, deployment, active[0]))
    return result


def template_environment(template, worker, configmaps):
    values = {}
    secret_cache = {}

    def source(kind, reference):
        name = reference['name']
        try:
            if kind == 'configMap':
                return resource(configmaps['items'], name).get('data', {})
            if name not in secret_cache:
                secret_cache[name] = get('secret', name)
            return {key: base64.b64decode(value, validate=True).decode()
                    for key, value in secret_cache[name].get('data', {}).items()}
        except (KeyError, ValueError):
            if reference.get('optional'):
                return {}
            raise

    for entry in worker.get('envFrom', []):
        kind = 'configMap' if 'configMapRef' in entry else 'secret'
        reference = entry.get('configMapRef') or entry.get('secretRef')
        if reference is None:
            raise ValueError('Environment source')
        prefix = entry.get('prefix', '')
        values.update({prefix + key: value for key, value in source(kind, reference).items()})
    for entry in worker.get('env', []):
        name = entry['name']
        if 'valueFrom' not in entry:
            value = entry.get('value', '').replace('$$', chr(0))
            value = re.sub(r'\$\(([A-Za-z_][A-Za-z_0-9]*)\)',
                           lambda match: values.get(match.group(1), match.group(0)) or match.group(0), value)
            values[name] = value.replace(chr(0), '$')
            continue
        reference = entry['valueFrom']
        key_ref = reference.get('configMapKeyRef') or reference.get('secretKeyRef')
        if key_ref is not None:
            kind = 'configMap' if 'configMapKeyRef' in reference else 'secret'
            data = source(kind, key_ref)
            if key_ref['key'] in data:
                values[name] = data[key_ref['key']]
            elif not key_ref.get('optional'):
                raise ValueError('Environment key')
        elif 'fieldRef' in reference:
            path = reference['fieldRef'].get('fieldPath', '')
            match = re.fullmatch(r"metadata\.(labels|annotations)\['([^']+)'\]", path)
            values[name] = template.get('metadata', {}).get(match.group(1), {}).get(match.group(2)) if match else None
        else:
            values[name] = None
    return values
try:
    deployments = get('deployments')
    replicasets = get('replicasets')
    pods = get('pods')
    active = consumers(deployments, replicasets, pods)
    before = {}
    for role, _, pod in active:
        name = pod['metadata']['name']
        before[name] = int(command(['kubectl', 'exec', name, '-c', 'worker', '--',
                                    'cat', contract['counterPath']]).strip())
        response = json.loads(command(['kubectl', 'exec', name, '-c', 'worker', '--',
                                       'wget', '-qO-', '-T', '2', contract['snapshotURL']]))
        result = response.get('data', {}).get('result', [])
        valid = response.get('status') == 'success' and response.get('data', {}).get('resultType') == 'vector' and len(result) == 1
        if valid:
            value = Decimal(str(result[0]['value'][1]))
            valid = value.is_finite() and value == role['expected']
        require(valid, 'observer_delivery')
    if deadline - time.monotonic() < 1.1:
        raise ValueError('Observation progress budget exhausted')
    time.sleep(1.1)
    for _, _, pod in active:
        name = pod['metadata']['name']
        after = int(command(['kubectl', 'exec', name, '-c', 'worker', '--',
                             'cat', contract['counterPath']]).strip())
        require(after > before[name] >= 0, 'observer_progress')
except (KeyError, ValueError, TypeError, AttributeError, IndexError, InvalidOperation, OSError, subprocess.SubprocessError):
    require(False, 'observer_delivery')
sys.exit(failed)
DQ_OBSERVER_DELIVERY
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
set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
url=$(jq -r '.url // ""' /run/dq/facts/0/prometheus-target.json 2>/dev/null || true)
sum=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=sum%28station_queue_depth%7Bjob%3D%22board%22%2Croute%3D%22north%22%7D%29" 2>/dev/null || true)
count=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=count%28station_queue_depth%7Bjob%3D%22board%22%2Croute%3D%22north%22%7D%29" 2>/dev/null || true)
query=sum
  case "$query" in up) doc=$up; expected=1;; sum) doc=$sum; expected=7;; count) doc=$count; expected=2;; esac
  check "${query}_status" "$query query status = success" '.status=="success"' "$doc"
  check "${query}_count" "$query query returns one result" '(.data.result|length)==1' "$doc"
  if ! jq -e --arg expected "$expected" '.data.result[0].value[1]==$expected' <<<"$doc" >/dev/null 2>&1; then printf '%s\n' "$query query value = $expected: ✗ [DQ:${query}_value]"; failed=1; fi
query=count
  case "$query" in up) doc=$up; expected=1;; sum) doc=$sum; expected=7;; count) doc=$count; expected=2;; esac
  check "${query}_status" "$query query status = success" '.status=="success"' "$doc"
  check "${query}_count" "$query query returns one result" '(.data.result|length)==1' "$doc"
  if ! jq -e --arg expected "$expected" '.data.result[0].value[1]==$expected' <<<"$doc" >/dev/null 2>&1; then printf '%s\n' "$query query value = $expected: ✗ [DQ:${query}_value]"; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
