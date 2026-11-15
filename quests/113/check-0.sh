set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
class=$(jq -r '.class // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
url=$(jq -r '.url // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
gateway=$(kubectl get gateway station -o json 2>/dev/null || true)
route=$(kubectl get httproute board -o json 2>/dev/null || true)
if ! test -n "$class" || ! jq -e --arg class "$class" '.spec.gatewayClassName==$class' <<<"$gateway" >/dev/null 2>&1; then printf '%s\n' 'gateway/station class = supplied private class: ✗ [DQ:class]'; failed=1; fi
check 'gateway/station Accepted=True at current generation [DQ:accepted]' '. as $gw | any(.status.conditions[]?;.type=="Accepted" and .status=="True" and .observedGeneration==$gw.metadata.generation)' "$gateway"
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
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY_NETWORK_113_1'
set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
class=$(jq -r '.class // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
url=$(jq -r '.url // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
gateway=$(kubectl get gateway station -o json 2>/dev/null || true)
route=$(kubectl get httproute board -o json 2>/dev/null || true)
check 'httproute/board first parent = station [DQ:parent]' '(.metadata.namespace//"") as $ns | any(.spec.parentRefs[]?; .name=="station" and (.group//"gateway.networking.k8s.io")=="gateway.networking.k8s.io" and (.kind//"Gateway")=="Gateway" and (.namespace==null or .namespace==$ns))' "$route"
check 'httproute/board hostnames = [north.station.internal] [DQ:hostnames]' '(.spec.hostnames|type)=="array" and (.spec.hostnames|unique)==["north.station.internal"]' "$route"
check 'httproute/board first backend name = board [DQ:backend_name]' '(.metadata.namespace//"") as $ns | (.spec.rules|length)>0 and all(.spec.rules[]; (.backendRefs|length)>0 and all(.backendRefs[] | select((.weight//1)>0); .name=="board" and (.kind//"Service")=="Service" and (.group//"")=="" and (.namespace==null or .namespace==$ns) and (.weight//1)>=0) and any(.backendRefs[]; (.weight//1)>0))' "$route"
check 'httproute/board first backend port = 8080 [DQ:backend_port]' '(.spec.rules|length)>0 and all(.spec.rules[]; (.backendRefs|length)>0 and any(.backendRefs[]; (.weight//1)>0) and all(.backendRefs[] | select((.weight//1)>0); .port==8080))' "$route"
check 'httproute/board a parent Accepted=True [DQ:parent_accepted]' 'any(.status.parents[]?;any(.conditions[]?;.type=="Accepted" and .status=="True"))' "$route"
check 'httproute/board a parent ResolvedRefs=True [DQ:parent_resolved]' 'any(.status.parents[]?;any(.conditions[]?;.type=="ResolvedRefs" and .status=="True"))' "$route"
check 'httproute/board one parent has both conditions [DQ:parent_both]' 'any(.status.parents[]?;any(.conditions[]?;.type=="Accepted" and .status=="True") and any(.conditions[]?;.type=="ResolvedRefs" and .status=="True"))' "$route"
exit "$failed"
DQ_LEGACY_NETWORK_113_1
python3 -I - <<'DQ_ATTACHMENT_CURRENT'
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
try:
    facts = json.loads(Path('/run/dq/facts/0/attachment-identities.json').read_text())
    contract = facts['contract']
    gateway = get('gateway', contract['gateway'])
    route = get('httproute', contract['route'])
    service = get('service', contract['backendService'])
    deployments = get('deployments')
    replicasets = get('replicasets')
    pods = get('pods')
    require(gateway['metadata']['uid'] == facts['gatewayUID']
            and route['metadata']['uid'] == facts['routeUID']
            and service['metadata']['uid'] == facts['serviceUID']
            and preserved(facts, deployments, replicasets, pods), 'attachment_identity')
    require(gateway['spec']['listeners'] == facts['listeners'], 'attachment_listener')

    def parent_key(value):
        return (value.get('group') or 'gateway.networking.k8s.io',
                value.get('kind') or 'Gateway', value.get('namespace') or namespace,
                value.get('name'), value.get('sectionName'), value.get('port'))

    requested = [parent_key(parent) for parent in route['spec'].get('parentRefs', [])]
    generation = route['metadata']['generation']
    matching = []
    for parent in route.get('status', {}).get('parents', []):
        key = parent_key(parent.get('parentRef', {}))
        if (key[:4] != ('gateway.networking.k8s.io', 'Gateway', namespace, contract['gateway'])
                or parent.get('controllerName') != facts['controller']):
            continue
        compatible = []
        for request in requested:
            if request[:4] != key[:4]:
                continue
            if any(left is not None and right is not None and left != right
                   for left, right in zip(request[4:], key[4:])):
                continue
            section = request[4] if request[4] is not None else key[4]
            port = request[5] if request[5] is not None else key[5]
            compatible.extend(listener for listener in gateway['spec']['listeners']
                              if listener.get('protocol') == 'HTTP'
                              and (section is None or listener['name'] == section)
                              and (port is None or listener['port'] == port))
        if not compatible:
            continue
        conditions = parent.get('conditions', [])
        matching.append(all(any(condition.get('type') == kind and condition.get('status') == 'True'
                                and condition.get('observedGeneration') == generation
                                for condition in conditions)
                            for kind in ('Accepted', 'ResolvedRefs')))
    require(bool(matching), 'attachment_parent')
    require(any(matching), 'attachment_generation')
except (KeyError, ValueError, TypeError, AttributeError, OSError, subprocess.SubprocessError):
    require(False, 'attachment_parent')
sys.exit(failed)
DQ_ATTACHMENT_CURRENT
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
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
class=$(jq -r '.class // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
url=$(jq -r '.url // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
gateway=$(kubectl get gateway station -o json 2>/dev/null || true)
route=$(kubectl get httproute board -o json 2>/dev/null || true)
if ! test -n "$url" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 --header='Host: north.station.internal' "$url" 2>/dev/null)" = north-113; then printf '%s\n' 'matching Host response = north-113: ✗ [DQ:http]'; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
class=$(jq -r '.class // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
url=$(jq -r '.url // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
gateway=$(kubectl get gateway station -o json 2>/dev/null || true)
route=$(kubectl get httproute board -o json 2>/dev/null || true)
if test -n "$url" && timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 --header='Host: closed.station.internal' "$url" >/dev/null 2>&1; then printf '%s\n' 'other Host request fails: ✗ [DQ:wrong]'; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
