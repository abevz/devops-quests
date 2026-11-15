set -euo pipefail
cd ~/quest
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
if ! (
kubectl rollout status deployment/relay --timeout=3s >/dev/null
); then
  printf '%s\n' 'The workload condition is unmet: ✗ [DQ:progressive_producer]'
  exit 1
fi
python3 -I - <<'DQ_PROPERTY'
PHASE = 0
import json
import subprocess
import sys
from pathlib import Path

from dq_check import workload_worker

failed = False

def require(value, marker):
    global failed
    if not value:
        print('Publication requirement is unmet: ✗ [DQ:' + marker + ']')
        failed = True

def command(args, marker):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=15)
        if result.returncode:
            raise ValueError('Current observation is unavailable')
        return result.stdout
    except (ValueError, OSError, subprocess.SubprocessError):
        print('Current publication inputs are unavailable: ✗ [DQ:' + marker + ']')
        sys.exit(1)

def document(args, marker):
    try:
        return json.loads(command(args, marker))
    except ValueError:
        print('Current publication document is invalid: ✗ [DQ:' + marker + ']')
        sys.exit(1)

def get(kind, name, marker='progressive_source'):
    return document(['kubectl', 'get', kind, name, '-o', 'json'], marker)

def projected(document, source):
    names = set()
    for volume in document.get('spec', {}).get('template', {}).get('spec', {}).get('volumes', []):
        sources = [volume.get('configMap', {})] + [v.get('configMap', {}) for v in volume.get('projected', {}).get('sources', [])]
        if any(v.get('name') == source for v in sources):
            names.add(volume.get('name'))
    return any(m.get('name') in names for m in workload_worker(document).get('volumeMounts', []))

def source_environment(document, name, source):
    worker = workload_worker(document)
    explicit = [v for v in worker.get('env', []) if v.get('name') == name]
    if explicit:
        ref = explicit[-1].get('valueFrom', {}).get('configMapKeyRef', {})
        return ref.get('name') == source and ref.get('key') == name
    # Kubernetes resolves envFrom in order: later sources override earlier
    # keys, while explicit env above overrides every envFrom source.
    for entry in reversed(worker.get('envFrom', [])):
        prefix = entry.get('prefix', '')
        if not name.startswith(prefix):
            continue
        key = name[len(prefix):]
        for reference, kind in [('configMapRef', 'configmap'), ('secretRef', 'secret')]:
            ref = entry.get(reference, {})
            if not ref.get('name'):
                continue
            raw = command(['kubectl', 'get', kind, ref['name'], '--ignore-not-found', '-o', 'json'], 'progressive_consumer')
            document = json.loads(raw or '{}')
            if key in document.get('data', {}):
                return kind == 'configmap' and ref['name'] == source and key == name
    return False

def selector_matches(selector, labels):
    return bool(selector) and all(labels.get(k) == v for k, v in selector.items())

def ready_pods(deployment, pods, replicasets):
    rs = {v.get('metadata', {}).get('uid') for v in replicasets if any(o.get('controller') is True and o.get('kind') == 'Deployment' and o.get('uid') == deployment.get('metadata', {}).get('uid') for o in v.get('metadata', {}).get('ownerReferences', []))}
    return [p for p in pods if any(o.get('controller') is True and o.get('kind') == 'ReplicaSet' and o.get('uid') in rs for o in p.get('metadata', {}).get('ownerReferences', [])) and p.get('metadata', {}).get('deletionTimestamp') is None and any(c.get('type') == 'Ready' and c.get('status') == 'True' for c in p.get('status', {}).get('conditions', []))]

def payload(pod, uri):
    return document(['kubectl', 'exec', pod['metadata']['name'], '-c', 'worker', '--', 'wget', '-qO-', '-T', '3', uri], 'progressive_publication')

facts = json.loads(Path('/run/dq/facts/0/progressive-identities.json').read_text())
contract = facts['contract']
source = contract['producer']['sourceConfigMap']
producer = get('deployment', contract['producer']['deployment'], 'progressive_producer')
cm = get('configmap', source)
service = get('service', contract['publicService']['name'], 'progressive_service')
require(producer.get('metadata', {}).get('uid') == facts['producer_uid'] and cm.get('metadata', {}).get('uid') == facts['source_uid'], 'progressive_identity')
require(all(cm.get('data', {}).get(k) == v for k, v in facts['data'].items()), 'progressive_source')
require(projected(producer, source), 'progressive_projection')
expected = json.loads(facts['data']['release.json'])
active = producer
if PHASE == 1:
    retained = json.loads(Path('/run/dq/facts/1/failover-identities.json').read_text())
    active = get('deployment', contract['consumer']['deployment'], 'progressive_consumer')
    require(active.get('metadata', {}).get('uid') == retained['consumer_uid'] and service.get('metadata', {}).get('uid') == retained['service_uid'], 'progressive_identity')
    require(projected(active, source) and all(source_environment(active, name, source) for name in contract['consumerEnvironment']), 'progressive_consumer')
    command(['kubectl', 'rollout', 'status', 'deployment/' + contract['producer']['deployment'], '--timeout=3s'], 'progressive_producer')
    command(['kubectl', 'rollout', 'status', 'deployment/' + contract['consumer']['deployment'], '--timeout=3s'], 'progressive_consumer')
ports = [p for p in service.get('spec', {}).get('ports', []) if p.get('port') == contract['publicService']['port'] and p.get('protocol', 'TCP') == 'TCP']
selector = service.get('spec', {}).get('selector', {})
require(service.get('spec', {}).get('type', 'ClusterIP') == 'ClusterIP' and len(ports) == 1 and selector_matches(selector, active.get('spec', {}).get('template', {}).get('metadata', {}).get('labels', {})), 'progressive_service')
pods = document(['kubectl', 'get', 'pods', '-o', 'json'], 'progressive_service')['items']
replicasets = document(['kubectl', 'get', 'replicasets', '-o', 'json'], 'progressive_service')['items']
active_pods = ready_pods(active, pods, replicasets)
active_ids = {p['metadata']['uid'] for p in active_pods}
slices = document(['kubectl', 'get', 'endpointslices', '-l', 'kubernetes.io/service-name=' + contract['publicService']['name'], '-o', 'json'], 'progressive_service')['items']
endpoints = [e for s in slices if any(o.get('kind') == 'Service' and o.get('uid') == service['metadata']['uid'] for o in s.get('metadata', {}).get('ownerReferences', [])) for e in s.get('endpoints', []) if e.get('conditions', {}).get('ready') is not False]
require(bool(active_pods) and bool(endpoints) and all(e.get('targetRef', {}).get('kind') == 'Pod' and e.get('targetRef', {}).get('uid') in active_ids for e in endpoints), 'progressive_service')
if not active_pods:
    sys.exit(1)
pod = active_pods[0]
base = 'http://' + contract['publicService']['name'] + ':' + str(contract['publicService']['port'])
require(payload(pod, base + contract['producerPath']) == expected, 'progressive_publication')
if PHASE == 1:
    for name in contract['consumerEnvironment']:
        actual = command(['kubectl', 'exec', pod['metadata']['name'], '-c', 'worker', '--', 'printenv', name], 'progressive_consumer').strip()
        require(actual == facts['data'][name], 'progressive_consumer')
    require(payload(pod, base + contract['consumerPath']) == expected, 'progressive_consumer')
    producer_pods = ready_pods(producer, pods, replicasets)
    require(bool(producer_pods), 'progressive_producer')
    if producer_pods:
        require(payload(producer_pods[0], 'http://127.0.0.1:' + str(retained['producer_port']) + contract['producerPath']) == expected, 'progressive_producer')
sys.exit(int(failed))
DQ_PROPERTY
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
