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
document=$(kubectl get deployment relay -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 3<<<"$document" <<'DQ_QUANTITY'
import json, sys
from decimal import InvalidOperation
from dq_check import quantity, read_argument, workload_worker as worker

sys.argv = [read_argument(value) for value in sys.argv]

try:
    resources=worker(json.loads(sys.argv[1])).get("resources",{})
except (KeyError,ValueError,TypeError,AttributeError):
    resources={}
failed=False
for category,name,expected,marker,label in [('limits', 'memory', '96Mi', None, None)]:
    try:
        ok=quantity(resources.get(category,{}).get(name), dialect="typed_ascii")==quantity(expected, dialect="typed_ascii")
    except (KeyError,ValueError,TypeError,AttributeError,InvalidOperation,OverflowError):
        ok=False
    if not ok:
        failed=True
        if marker:
            print(label+": ✗ [DQ:"+marker+"]")
sys.exit(failed)
DQ_QUANTITY
python3 -I - <<'DQ_MEMORY_BUDGET'
import json
import subprocess
import sys
from decimal import InvalidOperation
from pathlib import Path

from dq_check import pod_worker, quantity, workload_worker

failed = False

def require(value, marker):
    global failed
    if not value:
        print('Startup condition is unmet: ✗ [DQ:' + marker + ']')
        failed = True

def command(args, marker):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=15)
        if result.returncode:
            raise ValueError('Current startup observation failed')
        return result.stdout
    except (ValueError, OSError, subprocess.SubprocessError):
        print('Current startup inputs are unavailable: ✗ [DQ:' + marker + ']')
        sys.exit(1)

def document(args, marker):
    return json.loads(command(args, marker))

def get(kind, name, marker='startup_identity'):
    return document(['kubectl', 'get', kind, name, '-o', 'json'], marker)

def same_image(actual, expected):
    digest = expected.partition('@')[2]
    return actual == expected or bool(digest) and isinstance(actual, str) and actual.partition('@')[2] == digest

def ready_pods(deployment, pods, replicasets):
    uid = deployment.get('metadata', {}).get('uid')
    owners = {r.get('metadata', {}).get('uid') for r in replicasets if any(o.get('kind') == 'Deployment' and o.get('uid') == uid and o.get('controller') is True for o in r.get('metadata', {}).get('ownerReferences', []))}
    return [p for p in pods if not p.get('metadata', {}).get('deletionTimestamp') and any(o.get('kind') == 'ReplicaSet' and o.get('uid') in owners and o.get('controller') is True for o in p.get('metadata', {}).get('ownerReferences', [])) and any(c.get('type') == 'Ready' and c.get('status') == 'True' for c in p.get('status', {}).get('conditions', []))]

def budget(spec):
    try:
        ceiling = quantity(contract['memory']['podCeiling'], dialect='typed_ascii')
        parent = spec.get('resources', {}).get('limits', {}).get('memory')
        parent = quantity(parent, dialect='typed_ascii') if parent is not None else None
        if parent is not None and not 0 < parent <= ceiling:
            return False
        def limit(container):
            declared = container.get('resources', {}).get('limits', {}).get('memory')
            if declared is None and parent is not None:
                return 0
            value = quantity(declared, dialect='typed_ascii')
            if not 0 < value <= ceiling:
                raise ValueError('Container is outside the supplied memory envelope')
            return value
        main = sum(limit(c) for c in spec.get('containers', []))
        sidecars = 0
        peak_init = 0
        for container in spec.get('initContainers', []):
            value = limit(container)
            if container.get('restartPolicy') == 'Always':
                sidecars += value
                peak_init = max(peak_init, sidecars)
            else:
                peak_init = max(peak_init, sidecars + value)
        return bool(spec.get('containers')) and (parent is not None or max(main + sidecars, peak_init) <= ceiling)
    except (ValueError, KeyError, TypeError, AttributeError, InvalidOperation, OverflowError):
        return False


facts = json.loads(Path('/run/dq/facts/0/startup-identities.json').read_text())
contract = facts['contract']
for key, original in facts['identities'].items():
    kind, name = key.split('/', 1)
    current = get(kind, name)
    require(current.get('metadata', {}).get('uid') == original, 'startup_identity')
    if kind == 'deployment':
        require(budget(current.get('spec', {}).get('template', {}).get('spec', {})), 'startup_budget')
        require(same_image(workload_worker(current).get('image'), facts['image']), 'startup_image')
for role in contract['roles']:
    deployment = get('deployment', role['deployment'])
    if role.get('initializer'):
        initializers = [c for c in deployment.get('spec', {}).get('template', {}).get('spec', {}).get('initContainers', []) if c.get('name') == role['initializer']]
        require(len(initializers) == 1 and same_image(initializers[0].get('image'), facts['image']) and initializers[0].get('restartPolicy') != 'Always', 'startup_initializer')
source = get('configmap', contract['sourceConfigMap'], 'startup_source')
require(all(source.get('data', {}).get(k) == v for k, v in facts['policy'].items()), 'startup_source')
sys.exit(int(failed))
DQ_MEMORY_BUDGET
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
set +e
(
set -euo pipefail
kubectl rollout status deployment/relay --timeout=3s >/dev/null
)
dq_legacy_status=$?
set -e
if [ "$dq_legacy_status" -ne 0 ]; then
 printf '%s\n' 'The producer rollout is incomplete: ✗ [DQ:startup_payload]'
 exit 1
fi
python3 -I - <<'DQ_MEMORY_DATA'
import json
import subprocess
import sys
from decimal import InvalidOperation
from pathlib import Path

from dq_check import pod_worker, quantity, workload_worker

failed = False

def require(value, marker):
    global failed
    if not value:
        print('Startup condition is unmet: ✗ [DQ:' + marker + ']')
        failed = True

def command(args, marker):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=15)
        if result.returncode:
            raise ValueError('Current startup observation failed')
        return result.stdout
    except (ValueError, OSError, subprocess.SubprocessError):
        print('Current startup inputs are unavailable: ✗ [DQ:' + marker + ']')
        sys.exit(1)

def document(args, marker):
    return json.loads(command(args, marker))

def get(kind, name, marker='startup_identity'):
    return document(['kubectl', 'get', kind, name, '-o', 'json'], marker)

def same_image(actual, expected):
    digest = expected.partition('@')[2]
    return actual == expected or bool(digest) and isinstance(actual, str) and actual.partition('@')[2] == digest

def ready_pods(deployment, pods, replicasets):
    uid = deployment.get('metadata', {}).get('uid')
    owners = {r.get('metadata', {}).get('uid') for r in replicasets if any(o.get('kind') == 'Deployment' and o.get('uid') == uid and o.get('controller') is True for o in r.get('metadata', {}).get('ownerReferences', []))}
    return [p for p in pods if not p.get('metadata', {}).get('deletionTimestamp') and any(o.get('kind') == 'ReplicaSet' and o.get('uid') in owners and o.get('controller') is True for o in p.get('metadata', {}).get('ownerReferences', [])) and any(c.get('type') == 'Ready' and c.get('status') == 'True' for c in p.get('status', {}).get('conditions', []))]

def budget(spec):
    try:
        ceiling = quantity(contract['memory']['podCeiling'], dialect='typed_ascii')
        parent = spec.get('resources', {}).get('limits', {}).get('memory')
        parent = quantity(parent, dialect='typed_ascii') if parent is not None else None
        if parent is not None and not 0 < parent <= ceiling:
            return False
        def limit(container):
            declared = container.get('resources', {}).get('limits', {}).get('memory')
            if declared is None and parent is not None:
                return 0
            value = quantity(declared, dialect='typed_ascii')
            if not 0 < value <= ceiling:
                raise ValueError('Container is outside the supplied memory envelope')
            return value
        main = sum(limit(c) for c in spec.get('containers', []))
        sidecars = 0
        peak_init = 0
        for container in spec.get('initContainers', []):
            value = limit(container)
            if container.get('restartPolicy') == 'Always':
                sidecars += value
                peak_init = max(peak_init, sidecars)
            else:
                peak_init = max(peak_init, sidecars + value)
        return bool(spec.get('containers')) and (parent is not None or max(main + sidecars, peak_init) <= ceiling)
    except (ValueError, KeyError, TypeError, AttributeError, InvalidOperation, OverflowError):
        return False


facts = json.loads(Path('/run/dq/facts/0/startup-identities.json').read_text())
contract = facts['contract']
pods = document(['kubectl', 'get', 'pods', '-o', 'json'], 'startup_payload')['items']
replicasets = document(['kubectl', 'get', 'replicasets', '-o', 'json'], 'startup_payload')['items']
for role in contract['roles']:
    name = role['deployment']
    payload_marker = 'startup_payload_' + name
    publication_marker = 'startup_publication_' + name
    deployment = get('deployment', name, payload_marker)
    command(['kubectl', 'rollout', 'status', 'deployment/' + name, '--timeout=3s'], payload_marker)
    current = ready_pods(deployment, pods, replicasets)
    require(bool(current), payload_marker)
    service = get('service', role['service'], 'startup_service')
    selector = service.get('spec', {}).get('selector', {})
    labels = deployment.get('spec', {}).get('template', {}).get('metadata', {}).get('labels', {})
    ports = [p for p in service.get('spec', {}).get('ports', []) if p.get('port') == contract['servicePort'] and p.get('protocol', 'TCP') == 'TCP']
    require(service.get('spec', {}).get('type', 'ClusterIP') == contract['serviceType'] and bool(selector) and all(labels.get(k) == v for k, v in selector.items()) and len(ports) == 1, 'startup_service')
    for pod in current:
        pod_name = pod['metadata']['name']
        require(budget(pod.get('spec', {})), 'startup_budget')
        require(same_image(pod_worker(pod).get('image'), facts['image']), 'startup_image')
        if role.get('initializer'):
            statuses = [s for s in pod.get('status', {}).get('initContainerStatuses', []) if s.get('name') == role['initializer']]
            require(len(statuses) == 1 and statuses[0].get('state', {}).get('terminated', {}).get('exitCode') == 0, 'startup_initializer')
        prefix = ['kubectl', 'exec', pod_name, '-c', 'worker', '--']
        filesystem = command(prefix + ['stat', '-f', '-c', '%T', contract['memoryPath']], payload_marker).strip()
        size = int(command(prefix + ['stat', '-c', '%s', contract['payloadPath']], payload_marker).strip())
        blocks = int(command(prefix + ['stat', '-c', '%b', contract['payloadPath']], payload_marker).strip())
        digest = command(prefix + ['sha256sum', contract['payloadPath']], payload_marker).split()[0]
        require(filesystem == contract['filesystem'] and size == contract['dataset']['bytes'] and blocks * 512 >= size and digest == contract['dataset']['sha256'], payload_marker)
        uri = 'http://' + role['service'] + ':' + str(contract['servicePort']) + contract['metadataPath']
        record = document(prefix + ['wget', '-qO-', '-T', '3', uri], publication_marker)
        require(isinstance(record, dict) and all(record.get(k) == v for k, v in facts['publication'].items()), publication_marker)
sys.exit(int(failed))
DQ_MEMORY_DATA
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
exit "$failed"
