set -euo pipefail
cd ~/quest
failed=0
if ! test -s /run/dq/facts/0/original-pvc-uid || ! test "$(kubectl get pvc ledger-shelf-0 -o jsonpath='{.metadata.uid}' 2>/dev/null)" = "$(cat /run/dq/facts/0/original-pvc-uid 2>/dev/null)"; then
  printf '%s\n' 'ledger-shelf-0 UID = /run/dq/facts/0/original-pvc-uid: ✗'
  failed=1
fi
if ! kubectl get service shelf -o json 2>/dev/null | jq -e '.spec.clusterIP=="None" and .spec.selector=={app:"shelf"}' >/dev/null 2>&1; then
  printf '%s\n' 'service/shelf clusterIP = None, selector = app:shelf: ✗'
  failed=1
fi
if ! policies=$(kubectl get networkpolicies -o json 2>/dev/null); then
  printf '%s\n' 'kubectl get networkpolicies: ✗'
  failed=1
  policies='{"items":[]}'
fi
if ! pods=$(kubectl get pods -l app=client -o json 2>/dev/null); then
  printf '%s\n' 'client Pods: ✗'
  failed=1
  pods='{"items":[]}'
fi
if ! python3 - "$policies" "$pods" "shelf" <<'DQ_POLICY'
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
    if not isinstance(value, dict) or set(value) - {"matchLabels", "matchExpressions"}:
        return False
    exact = dict(value.get("matchLabels", {}))
    expressions = value.get("matchExpressions", [])
    for expression in expressions:
        if expression.get("operator") != "In" or len(expression.get("values", [])) != 1:
            return False
        key, selected = expression.get("key"), expression["values"][0]
        if key in exact and exact[key] != selected:
            return False
        exact[key] = selected
    return exact == labels


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
                if set(port) - {"port", "protocol", "endPort"} or not isinstance(port.get("port"), int) or isinstance(port.get("port"), bool):
                    raise ValueError("unbounded or named port")
                number = port["port"]
                if port.get("endPort", number) != number:
                    raise ValueError("port range")
                result.add((destination, port.get("protocol", "TCP"), number))
    return result


def validate(document, pods, target):
    labels = [pod["metadata"]["labels"] for pod in pods["items"]]
    if not labels:
        return ["client Pods: ✗"]
    expected = {("dns", "UDP", 53), ("dns", "TCP", 53), (target, "TCP", 8080)}
    items = document["items"]
    named = [p for p in items if p.get("metadata", {}).get("name") == "client-egress"]
    errors = []
    if len(named) != 1:
        return ["networkpolicy/client-egress: ✗"]
    spec = named[0]["spec"]
    if not simple_selector(spec.get("podSelector"), {"app": "client"}):
        errors.append("client-egress podSelector = app:client: ✗")
    if set(spec.get("policyTypes", [])) != {"Egress"}:
        errors.append("client-egress policyTypes = [Egress]: ✗")
    try:
        actual = flows(spec, target)
    except (KeyError, TypeError, ValueError, AttributeError):
        errors.append("client-egress egress peers/ports: ✗")
    else:
        for destination, protocol, port in sorted(expected - actual):
            errors.append(f"client-egress {destination} {protocol} {port}: ✗")
        for destination, protocol, port in sorted(actual - expected):
            errors.append(f"client-egress {destination} {protocol} {port}: ✗")
    for policy in items:
        other = policy["spec"]
        if policy is named[0] or "Egress" not in other.get("policyTypes", []):
            continue
        try:
            if any(matches(other.get("podSelector", {}), pod_labels) for pod_labels in labels) and not flows(other, target) <= expected:
                errors.append("networkpolicy/" + policy.get("metadata", {}).get("name", "?") + " egress: ✗")
        except (KeyError, TypeError, ValueError, AttributeError):
            errors.append("networkpolicy/" + policy.get("metadata", {}).get("name", "?") + " selector/egress: ✗")
    return errors


try:
    problems = validate(json.loads(sys.argv[1]), json.loads(sys.argv[2]), sys.argv[3])
except (KeyError, TypeError, ValueError, AttributeError, json.JSONDecodeError):
    problems = ["networkpolicies / client Pod labels: ✗"]
if problems:
    print("\n".join(problems))
    sys.exit(1)
DQ_POLICY
then
  failed=1
fi
if ! timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- nslookup -type=A "shelf-0.shelf.$DQ_NAMESPACE.svc.cluster.local." >/dev/null 2>&1; then
  printf '%s\n' 'deployment/client DNS shelf-0.shelf: ✗'
  failed=1
fi
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://shelf-0.shelf:8080 2>/dev/null)" = ledger-120; then
  printf '%s\n' 'deployment/client → shelf-0.shelf:8080 = ledger-120: ✗'
  failed=1
fi
exit "$failed"
