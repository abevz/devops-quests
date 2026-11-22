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
helm get values board -o json | jq -e '(.readinessPort|tonumber)==8080' >/dev/null
python3 -I - <<'DQ_PROPERTY'
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml
from dq_check import port_number, workload_worker

failed = False

def require(value, marker):
    global failed
    if not value:
        print('Release requirement is unmet: ✗ [DQ:' + marker + ']')
        failed = True

def command(args, marker):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=30)
        if p.returncode:
            raise ValueError('Current release observation failed')
        return p.stdout
    except (ValueError, OSError, subprocess.SubprocessError):
        print('Current release inputs are unavailable: ✗ [DQ:' + marker + ']')
        sys.exit(1)

def document(args, marker):
    try:
        return json.loads(command(args, marker))
    except ValueError:
        print('Current release document is invalid: ✗ [DQ:' + marker + ']')
        sys.exit(1)

def named(docs, kind, name):
    found = [d for d in docs if isinstance(d, dict) and d.get('kind') == kind and d.get('metadata', {}).get('name') == name]
    if len(found) != 1:
        raise ValueError('Required release object is missing or duplicated')
    return found[0]

def same_image(actual, expected):
    digest = expected.partition('@')[2]
    return actual == expected or bool(digest) and isinstance(actual, str) and actual.partition('@')[2] == digest

def projected(deployment, source):
    names = {v.get('name') for v in deployment.get('spec', {}).get('template', {}).get('spec', {}).get('volumes', []) if v.get('configMap', {}).get('name') == source or any(s.get('configMap', {}).get('name') == source for s in v.get('projected', {}).get('sources', []))}
    return any(m.get('name') in names for m in workload_worker(deployment).get('volumeMounts', []))

def bundle(docs, message, readiness_port):
    deployment = named(docs, 'Deployment', contract['deployment'])
    cm = named(docs, 'ConfigMap', contract['configMap'])
    service = named(docs, 'Service', contract['service'])
    worker = workload_worker(deployment)
    probe = worker.get('readinessProbe', {})
    handler = probe.get('httpGet', probe.get('tcpSocket', {}))
    require(port_number([worker], handler.get('port')) == readiness_port, 'helm_values_contract')
    require(same_image(worker.get('image'), facts['image']), 'helm_image')
    require(projected(deployment, contract['configMap']), 'helm_projection')
    require(all(d.get('metadata', {}).get('namespace') in (None, '', os.environ['DQ_NAMESPACE']) for d in (deployment, cm, service)), 'helm_values_contract')
    data = cm.get('data', {})
    require(isinstance(data.get('index.html'), str) and data['index.html'].rstrip('\n') == message and json.loads(data.get('release.json', 'null')) == {'release_id': facts['release_id'], 'route': message}, 'helm_bundle')
    selector = service.get('spec', {}).get('selector', {})
    labels = deployment.get('spec', {}).get('template', {}).get('metadata', {}).get('labels', {})
    ports = [p for p in service.get('spec', {}).get('ports', []) if p.get('port') == contract['servicePort'] and p.get('protocol', 'TCP') == 'TCP']
    require(service.get('spec', {}).get('type', 'ClusterIP') == 'ClusterIP' and bool(selector) and all(labels.get(k) == v for k, v in selector.items()) and len(ports) == 1, 'helm_service')
    if len(ports) == 1:
        port_number(deployment['spec']['template']['spec']['containers'], ports[0].get('targetPort', ports[0]['port']))

facts = json.loads(Path('/run/dq/facts/0/helm-identities.json').read_text())
contract = json.loads(Path('/run/dq/facts/0/helm-contract.json').read_text())
import copy
import tempfile

values = document(['helm', 'get', 'values', contract['release'], '--all', '-o', 'json'], 'helm_values_contract')
require(isinstance(values, dict) and values.get('routeMessage') == contract['response'] and values.get('releaseId') == facts['release_id'] and same_image(values.get('image'), facts['image']), 'helm_values_contract')
for case in contract['renderCases']:
    supplied = copy.deepcopy(values)
    supplied.update(case)
    with tempfile.TemporaryDirectory() as directory:
        filename = Path(directory) / 'values.json'
        filename.write_text(json.dumps(supplied))
        args = ['helm', 'template', contract['release'], './chart', '--is-upgrade', '--namespace', os.environ['DQ_NAMESPACE'], '-f', str(filename)]
        rendered = command(args, 'helm_values_contract')
        # Identical inputs must not generate a different release definition.
        require(rendered == command(args, 'helm_values_contract'), 'helm_values_contract')
        bundle(list(yaml.safe_load_all(rendered)), case['routeMessage'], int(case['readinessPort']))
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
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
helm history board -o json | jq -e 'length>=3 and .[-1].status=="deployed"' >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The required deployed release history could not be verified: ✗ [DQ:helm_history]' >&2
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
test "$(kubectl get deployment board -o jsonpath='{.metadata.uid}')" = "$(cat /run/dq/facts/0/original-deployment-uid)"
python3 -I - <<'DQ_PROPERTY'
import json
import subprocess
import sys
from pathlib import Path

from dq_check import workload_worker

facts = json.loads(Path('/run/dq/facts/0/helm-identities.json').read_text())
contract = json.loads(Path('/run/dq/facts/0/helm-contract.json').read_text())
failed = False
for kind, name, key in [('deployment', contract['deployment'], 'deployment_uid'), ('configmap', contract['configMap'], 'source_uid'), ('service', contract['service'], 'service_uid')]:
    value = json.loads(subprocess.run(['kubectl', 'get', kind, name, '-o', 'json'], capture_output=True, text=True, check=True, timeout=15).stdout)
    if value.get('metadata', {}).get('uid') != facts[key]:
        print('Retain each original release object: ✗ [DQ:helm_identity]')
        failed = True
    if kind == 'deployment':
        image = workload_worker(value).get('image')
        digest = facts['image'].partition('@')[2]
        if not (image == facts['image'] or digest and isinstance(image, str) and image.partition('@')[2] == digest):
            print('Retain the supplied immutable application image: ✗ [DQ:helm_image]')
            failed = True
sys.exit(int(failed))
DQ_PROPERTY
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
  printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_2]'
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
live=$(kubectl get deployment board -o json 2>/dev/null || true)
rendered=$(helm get manifest board 2>/dev/null || true)
python3 -I - /dev/fd/3 /dev/fd/4 3<<<"$live" 4<<<"$rendered" <<'DQ_READINESS'
import sys

from dq_check import read_argument as _dq_read_argument

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys,math,re

from dq_check import workload_worker as _dq_worker

def worker(document):
    return _dq_worker(document, error="worker")



from dq_check import readiness_probe as readiness
import yaml
try:
    live=json.loads(sys.argv[1])
    rendered=[doc for doc in yaml.safe_load_all(sys.argv[2]) if isinstance(doc,dict) and doc.get("kind")=="Deployment" and doc.get("metadata",{}).get("name")=="board"]
    ok=len(rendered)==1 and readiness(live,tcp=True) and readiness(rendered[0],tcp=True)
except (ValueError,KeyError,TypeError,AttributeError,yaml.YAMLError):
    ok=False
sys.exit(not ok)
DQ_READINESS
python3 -I - <<'DQ_RELEASE_BUNDLE'
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml
from dq_check import port_number, workload_worker

failed = False

def require(value, marker):
    global failed
    if not value:
        print('Release requirement is unmet: ✗ [DQ:' + marker + ']')
        failed = True

def command(args, marker):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=30)
        if p.returncode:
            raise ValueError('Current release observation failed')
        return p.stdout
    except (ValueError, OSError, subprocess.SubprocessError):
        print('Current release inputs are unavailable: ✗ [DQ:' + marker + ']')
        sys.exit(1)

def document(args, marker):
    try:
        return json.loads(command(args, marker))
    except ValueError:
        print('Current release document is invalid: ✗ [DQ:' + marker + ']')
        sys.exit(1)

def named(docs, kind, name):
    found = [d for d in docs if isinstance(d, dict) and d.get('kind') == kind and d.get('metadata', {}).get('name') == name]
    if len(found) != 1:
        raise ValueError('Required release object is missing or duplicated')
    return found[0]

def same_image(actual, expected):
    digest = expected.partition('@')[2]
    return actual == expected or bool(digest) and isinstance(actual, str) and actual.partition('@')[2] == digest

def projected(deployment, source):
    names = {v.get('name') for v in deployment.get('spec', {}).get('template', {}).get('spec', {}).get('volumes', []) if v.get('configMap', {}).get('name') == source or any(s.get('configMap', {}).get('name') == source for s in v.get('projected', {}).get('sources', []))}
    return any(m.get('name') in names for m in workload_worker(deployment).get('volumeMounts', []))

def bundle(docs, message, readiness_port):
    deployment = named(docs, 'Deployment', contract['deployment'])
    cm = named(docs, 'ConfigMap', contract['configMap'])
    service = named(docs, 'Service', contract['service'])
    worker = workload_worker(deployment)
    probe = worker.get('readinessProbe', {})
    handler = probe.get('httpGet', probe.get('tcpSocket', {}))
    require(port_number([worker], handler.get('port')) == readiness_port, 'helm_values_contract')
    require(same_image(worker.get('image'), facts['image']), 'helm_image')
    require(projected(deployment, contract['configMap']), 'helm_projection')
    require(all(d.get('metadata', {}).get('namespace') in (None, '', os.environ['DQ_NAMESPACE']) for d in (deployment, cm, service)), 'helm_values_contract')
    data = cm.get('data', {})
    require(isinstance(data.get('index.html'), str) and data['index.html'].rstrip('\n') == message and json.loads(data.get('release.json', 'null')) == {'release_id': facts['release_id'], 'route': message}, 'helm_bundle')
    selector = service.get('spec', {}).get('selector', {})
    labels = deployment.get('spec', {}).get('template', {}).get('metadata', {}).get('labels', {})
    ports = [p for p in service.get('spec', {}).get('ports', []) if p.get('port') == contract['servicePort'] and p.get('protocol', 'TCP') == 'TCP']
    require(service.get('spec', {}).get('type', 'ClusterIP') == 'ClusterIP' and bool(selector) and all(labels.get(k) == v for k, v in selector.items()) and len(ports) == 1, 'helm_service')
    if len(ports) == 1:
        port_number(deployment['spec']['template']['spec']['containers'], ports[0].get('targetPort', ports[0]['port']))

facts = json.loads(Path('/run/dq/facts/0/helm-identities.json').read_text())
contract = json.loads(Path('/run/dq/facts/0/helm-contract.json').read_text())
rendered = command(['helm', 'get', 'manifest', contract['release']], 'helm_bundle')
docs = list(yaml.safe_load_all(rendered))
bundle(docs, contract['response'], 8080)
live = [document(['kubectl', 'get', kind, name, '-o', 'json'], 'helm_bundle') for kind, name in [('deployment', contract['deployment']), ('configmap', contract['configMap']), ('service', contract['service'])]]
bundle(live, contract['response'], 8080)
uri = 'http://' + contract['service'] + ':' + str(contract['servicePort']) + contract['metadataPath']
actual = document(['kubectl', 'exec', 'deployment/' + contract['deployment'], '-c', 'worker', '--', 'wget', '-qO-', '-T', '3', uri], 'helm_publication')
require(actual == {'release_id': facts['release_id'], 'route': contract['response']}, 'helm_publication')
sys.exit(int(failed))
DQ_RELEASE_BUNDLE
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_3]'
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
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The release workload rollout could not be verified: ✗ [DQ:helm_rollout]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
test "$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://127.0.0.1:8080)" = north-67
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The release worker response could not be verified: ✗ [DQ:helm_http]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
