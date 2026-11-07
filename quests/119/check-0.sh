set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! policies=$(kubectl get networkpolicies -o json 2>/dev/null); then
  printf '%s\n' 'kubectl get networkpolicies: ✗ [DQ:policies]'
  failed=1
  policies='{"items":[]}'
fi
if ! pods=$(kubectl get pods -l app=client -o json 2>/dev/null); then
  printf '%s\n' 'client Pods: ✗ [DQ:pods]'
  failed=1
  pods='{"items":[]}'
fi
target_pods=$(kubectl get pods -l app=board -o json 2>/dev/null || echo '{"items":[]}')
if ! python3 -I - /dev/fd/3 /dev/fd/4 "board" /dev/fd/5 3<<<"$policies" 4<<<"$pods" 5<<<"$target_pods" <<'DQ_POLICY'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json
import sys


def matches(selector, labels):
    if not isinstance(selector, dict) or set(selector) - {"matchLabels", "matchExpressions"}:
        raise ValueError("selector")
    for key, value in selector.get("matchLabels", {}).items():
        if labels.get(key) != value:
            return False
    for expression in selector.get("matchExpressions", []):
        key = expression.get("key")
        operator = expression.get("operator")
        values = expression.get("values", [])
        if operator == "In":
            result = key in labels and labels[key] in values
        elif operator == "NotIn":
            result = key not in labels or labels[key] not in values
        elif operator == "Exists":
            result = key in labels
        elif operator == "DoesNotExist":
            result = key not in labels
        else:
            raise ValueError("selector operator")
        if not result:
            return False
    return True


def simple_selector(value, labels):
    if not isinstance(value,dict) or set(value)-{'matchLabels','matchExpressions'}:return False
    matches=value.get('matchLabels',{})
    clauses=value.get('matchExpressions',[])
    if not isinstance(matches,dict) or not isinstance(clauses,list):return False
    if set(matches)-set(labels) or any(e.get('key') not in labels for e in clauses):return False
    for key,expected in labels.items():
        allowed={matches[key]} if key in matches else None
        exclusions=set();exists=key in matches
        for clause in clauses:
            if clause['key']!=key:continue
            operator=clause.get('operator');values=clause.get('values',[])
            if operator=='In':
                if not values:return False
                allowed=set(values) if allowed is None else allowed & set(values)
                exists=True
            elif operator=='NotIn':exclusions.update(values)
            elif operator=='Exists':exists=True
            else:return False
        if allowed is None or not exists or allowed-exclusions!={expected}:return False
    return True


def flows(spec, target):
    result = set()
    for rule in spec.get("egress", []):
        if set(rule) - {"to", "ports"} or not rule.get("to") or not rule.get("ports"):
            raise ValueError("unbounded egress rule")
        for peer in rule["to"]:
            keys = set(peer)
            if keys == {"namespaceSelector", "podSelector"} and simple_selector(peer["namespaceSelector"], {"kubernetes.io/metadata.name": "kube-system"}) and simple_selector(peer["podSelector"], {"k8s-app": "kube-dns"}):
                destination = "dns"
            elif keys == {"podSelector"} and simple_selector(peer["podSelector"], {"app": target}):
                destination = target
            else:
                raise ValueError("unbounded or unexpected destination")
            for port in rule["ports"]:
                if set(port)-{'port','protocol','endPort'}:raise ValueError('port fields')
                value=port.get('port');protocol=port.get('protocol','TCP')
                if type(value) is int:number=value
                elif isinstance(value,str) and destination=='dns':
                    # Protected pinned kind CoreDNS ports, not a player-editable resolver.
                    mapping={('dns','UDP'):53,('dns-tcp','TCP'):53}
                    number=mapping[(value,protocol)]
                elif isinstance(value,str) and destination==target:
                    candidates=[p for p in target_pods['items'] if p.get('metadata',{}).get('labels',{}).get('app')==target and not p.get('metadata',{}).get('deletionTimestamp')]
                    if not candidates:raise ValueError('target Pods')
                    resolved=[]
                    for pod in candidates:
                        ports=[entry['containerPort'] for container in pod['spec']['containers'] for entry in container.get('ports',[]) if entry.get('name')==value and entry.get('protocol','TCP')==protocol]
                        if len(ports)!=1:raise ValueError('named target port')
                        resolved+=ports
                    if len(set(resolved))!=1:raise ValueError('inconsistent target ports')
                    number=resolved[0]
                else:raise ValueError('unbounded port')
                if port.get("endPort", number) != number:
                    raise ValueError("port range")
                result.add((destination, port.get("protocol", "TCP"), number))
    return result


def validate(document, pods, target):
    labels = [pod["metadata"]["labels"] for pod in pods["items"]]
    if not labels:
        return ["client Pods: ✗ [DQ:pods]"]
    expected = {("dns", "UDP", 53), ("dns", "TCP", 53), (target, "TCP", 8080)}
    items = document["items"]
    named = [p for p in items if p.get("metadata", {}).get("name") == "client-egress"]
    errors = []
    if len(named) != 1:
        return ["networkpolicy/client-egress: ✗ [DQ:named]"]
    spec = named[0]["spec"]
    if not simple_selector(spec.get("podSelector"), {"app": "client"}):
        errors.append("client-egress podSelector = app:client: ✗ [DQ:selector]")
    if set(spec.get("policyTypes", [])) != {"Egress"}:
        errors.append("client-egress policyTypes = [Egress]: ✗ [DQ:types]")
    try:
        actual = flows(spec, target)
    except (KeyError, TypeError, ValueError, AttributeError):
        errors.append("client-egress egress peers/ports: ✗ [DQ:egress]")
    else:
        for destination, protocol, port in sorted(expected - actual):
            errors.append(f"client-egress {destination} {protocol} {port}: ✗ [DQ:missing_{destination}_{protocol.lower()}_{port}]")
        for destination, protocol, port in sorted(actual - expected):
            errors.append(f"client-egress {destination} {protocol} {port}: ✗ [DQ:unexpected]")
    for policy in items:
        other = policy["spec"]
        if policy is named[0] or "Egress" not in other.get("policyTypes", []):
            continue
        try:
            if any(matches(other.get("podSelector", {}), pod_labels) for pod_labels in labels) and not flows(other, target) <= expected:
                errors.append("networkpolicy/" + policy.get("metadata", {}).get("name", "?") + " egress: ✗ [DQ:other_egress]")
        except (KeyError, TypeError, ValueError, AttributeError):
            errors.append("networkpolicy/" + policy.get("metadata", {}).get("name", "?") + " selector/egress: ✗ [DQ:other_invalid]")
    return errors


try:
    target_pods=json.loads(sys.argv[4]) if len(sys.argv)>4 else {"items":[]}
    problems = validate(json.loads(sys.argv[1]), json.loads(sys.argv[2]), sys.argv[3])
except (KeyError, TypeError, ValueError, AttributeError, json.JSONDecodeError):
    problems = ["networkpolicies / client Pod labels: ✗ [DQ:invalid_input]"]
if problems:
    print("\n".join(problems))
    sys.exit(1)
DQ_POLICY
then
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- nslookup -type=A "board.$DQ_NAMESPACE.svc.cluster.local." >/dev/null 2>&1; then
  printf '%s\n' 'deployment/client DNS board: ✗ [DQ:dns]'
  failed=1
fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-119; then
  printf '%s\n' 'deployment/client → board:8080 = north-119: ✗ [DQ:http]'
  failed=1
fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
closed=$(kubectl get service closed -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if ! test -n "$closed" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 "http://$closed:8080" 2>/dev/null)" = closed-119; then
  printf '%s\n' 'deployment/board → closed:8080 = closed-119: ✗ [DQ:closed_direct]'
  failed=1
fi
if test -n "$closed" && timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 2 "http://$closed:8080" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/client → closed:8080 fails: ✗ [DQ:closed_denied]'
  failed=1
fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
