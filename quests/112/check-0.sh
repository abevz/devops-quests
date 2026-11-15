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
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY_LOAD_0'
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
document=$(kubectl get deployment board -o json 2>/dev/null || true)
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
for category,name,expected,marker,label in [('requests', 'cpu', '100m', 'request', 'board CPU request = 100m'), ('limits', 'cpu', '200m', 'limit', 'board CPU limit = 200m')]:
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
DQ_LEGACY_LOAD_0
python3 -I - <<'DQ_LOAD_INPUTS'
import hashlib
import json
import shlex
import subprocess
import sys
import time
from pathlib import Path

from dq_check import current_pods, named, pod_worker, workload_worker

failed = False
deadline = time.monotonic() + 10

def require(value, marker):
    global failed
    if not value:
        print('Autoscaling recovery condition is unmet: ✗ [DQ:' + marker + ']')
        failed = True

def command(args, marker):
    try:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError('Observation budget exhausted')
        result = subprocess.run(args, capture_output=True, text=True, timeout=min(6, remaining))
        if result.returncode:
            raise ValueError('Observation failed')
        return result.stdout
    except (OSError, ValueError, subprocess.SubprocessError):
        print('Current autoscaling observation is unavailable: ✗ [DQ:' + marker + ']')
        sys.exit(1)

def get(kind, name, marker):
    try:
        return json.loads(command(['kubectl', 'get', kind] + ([name] if name else []) + ['-o', 'json'], marker))
    except ValueError:
        print('Current autoscaling observation is invalid: ✗ [DQ:' + marker + ']')
        sys.exit(1)

facts = json.loads(Path('/run/dq/facts/0/autoscaling-identities.json').read_text())
contract = facts['contract']

def same_image(actual, expected):
    digest = expected.partition('@')[2]
    return actual == expected or (
        bool(digest) and isinstance(actual, str) and actual.partition('@')[2] == digest
    )
for name in (contract['server'], contract['client']):
    document = get('deployment', name, 'load_identity')
    require(document.get('metadata', {}).get('uid') ==
            facts['identities']['deployment/' + name], 'load_identity')
    try:
        valid = same_image(workload_worker(document).get('image'), facts['images'][name])
    except (KeyError, TypeError, ValueError, AttributeError):
        valid = False
    require(valid, 'load_implementation')
provider = get('configmap', contract['handler']['configMap'], 'load_implementation')
try:
    valid = (provider['metadata']['uid'] ==
             facts['identities']['configmap/' + contract['handler']['configMap']]
             and hashlib.sha256(provider['data'][contract['handler']['key']].encode()).hexdigest()
             == facts['handlerSHA256'])
except (KeyError, TypeError, ValueError, AttributeError):
    valid = False
require(valid, 'load_implementation')
sys.exit(int(failed))
DQ_LOAD_INPUTS
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
set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
hpa=$(timeout 2s kubectl get hpa board -o json 2>/dev/null || true)
check minimum 'HPA minReplicas = 1' '.spec.minReplicas==1' "$hpa"
check maximum 'HPA maxReplicas = 2' '.spec.maxReplicas==2' "$hpa"
check target 'HPA CPU target utilization = 50' '[.spec.metrics[]? | select((.type=="Resource" and .resource.name=="cpu") or (.type=="ContainerResource" and .containerResource.name=="cpu" and .containerResource.container=="worker")) | (.resource//.containerResource)] as $cpu | ($cpu|length)>0 and all($cpu[]; .target.type=="Utilization" and (.target.averageUtilization|type)=="number" and .target.averageUtilization>0) and ([$cpu[].target.averageUtilization]|min)==50' "$hpa"
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY_LOAD_2'
set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
hpa=$(timeout 2s kubectl get hpa board -o json 2>/dev/null || true)
check ready 'board readyReplicas = 2' '.status.readyReplicas==2' "$board"
check current 'HPA currentReplicas = 2' '.status.currentReplicas==2' "$hpa"
check desired 'HPA desiredReplicas = 2' '.status.desiredReplicas==2' "$hpa"
check metric 'HPA current CPU utilization > 50' 'any(.status.currentMetrics[]?; select((.type=="Resource" and .resource.name=="cpu") or (.type=="ContainerResource" and .containerResource.name=="cpu" and .containerResource.container=="worker")) | (.resource//.containerResource) | (.current.averageUtilization|type)=="number" and .current.averageUtilization>50)' "$hpa"
check active 'HPA ScalingActive = True' 'any(.status.conditions[]?;.type=="ScalingActive" and .status=="True")' "$hpa"
if ! timeout 2s kubectl top pods -l app=board --no-headers 2>/dev/null | grep -E '[0-9]+m' >/dev/null; then printf '%s\n' 'kubectl top pods shows CPU millicores: ✗ [DQ:top]'; failed=1; fi
exit "$failed"
DQ_LEGACY_LOAD_2
python3 -I - <<'DQ_LOAD_DEMAND'
import hashlib
import json
import shlex
import subprocess
import sys
import time
from pathlib import Path

from dq_check import current_pods, named, pod_worker, workload_worker

failed = False
deadline = time.monotonic() + 12

def require(value, marker):
    global failed
    if not value:
        print('Autoscaling recovery condition is unmet: ✗ [DQ:' + marker + ']')
        failed = True

def command(args, marker):
    try:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError('Observation budget exhausted')
        result = subprocess.run(args, capture_output=True, text=True, timeout=min(6, remaining))
        if result.returncode:
            raise ValueError('Observation failed')
        return result.stdout
    except (OSError, ValueError, subprocess.SubprocessError):
        print('Current autoscaling observation is unavailable: ✗ [DQ:' + marker + ']')
        sys.exit(1)

def get(kind, name, marker):
    try:
        return json.loads(command(['kubectl', 'get', kind] + ([name] if name else []) + ['-o', 'json'], marker))
    except ValueError:
        print('Current autoscaling observation is invalid: ✗ [DQ:' + marker + ']')
        sys.exit(1)

facts = json.loads(Path('/run/dq/facts/0/autoscaling-identities.json').read_text())
contract = facts['contract']

def same_image(actual, expected):
    digest = expected.partition('@')[2]
    return actual == expected or (
        bool(digest) and isinstance(actual, str) and actual.partition('@')[2] == digest
    )
hpa = get('hpa', contract['hpa'], 'load_target')
reference = hpa.get('spec', {}).get('scaleTargetRef', {})
require(hpa.get('metadata', {}).get('uid') == facts['identities']['hpa/' + contract['hpa']]
        and reference.get('apiVersion') == 'apps/v1'
        and reference.get('kind') == 'Deployment'
        and reference.get('name') == contract['server'], 'load_target')
deployment = get('deployment', contract['server'], 'load_workers')
sets = get('replicasets', '', 'load_workers')
pods = get('pods', '', 'load_workers')
try:
    current = current_pods(deployment, sets, pods)
    valid = (deployment['metadata']['uid'] ==
             facts['identities']['deployment/' + contract['server']]
             and deployment['spec'].get('replicas') == contract['replicas']['max']
             and len(current) == contract['replicas']['max'])
    for pod in current:
        worker = pod_worker(pod)
        status = named(pod.get('status', {}).get('containerStatuses', []), 'worker')
        valid = valid and (
            pod.get('status', {}).get('phase') == 'Running'
            and status.get('ready') is True
            and isinstance(status.get('state', {}).get('running'), dict)
            and same_image(worker.get('image'), facts['images'][contract['server']])
        )
except (KeyError, TypeError, ValueError, AttributeError):
    valid, current = False, []
require(valid, 'load_workers')
counter = shlex.quote(contract['handler']['progress'])
path = shlex.quote(contract['handler']['path'])
counter_script = 'if test -f ' + counter + '; then wc -l < ' + counter + '; else printf "0\\n"; fi'
before = {}
for pod in current:
    name = pod['metadata']['name']
    output = command(['kubectl', 'exec', '--pod-running-timeout=2s', name, '-c', 'worker',
                      '--', 'sh', '-c', 'sha256sum ' + path + '; ' + counter_script], 'load_progress')
    try:
        lines = output.splitlines()
        require(lines[0].split()[0] == facts['handlerSHA256'], 'load_implementation')
        before[name] = int(lines[1])
        require(before[name] >= 0, 'load_progress')
    except (IndexError, TypeError, ValueError):
        require(False, 'load_progress')
remaining = deadline - time.monotonic()
if remaining <= 1:
    require(False, 'load_progress')
else:
    time.sleep(1)
    delta = 0
    for name, initial in before.items():
        output = command(['kubectl', 'exec', '--pod-running-timeout=2s', name, '-c', 'worker',
                          '--', 'sh', '-c', counter_script], 'load_progress')
        try:
            final = int(output.strip())
            require(final >= initial, 'load_progress')
            delta += max(0, final - initial)
        except (TypeError, ValueError):
            require(False, 'load_progress')
    require(delta > 0, 'load_progress')
sys.exit(int(failed))
DQ_LOAD_DEMAND
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
set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
hpa=$(timeout 2s kubectl get hpa board -o json 2>/dev/null || true)
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-112; then printf '%s\n' 'board:8080 = north-112: ✗ [DQ:http]'; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
