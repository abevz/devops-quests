"""Offline validation primitives shared by quest checks.

Explicit dialects preserve existing predicates; callers retain their diagnostics,
input collection and waits.
"""

import base64
import json
import os
import re
import stat
import subprocess
from decimal import Decimal
from pathlib import Path


def _quantity_typed_ascii(value):
    if isinstance(value, bool) or not isinstance(value, (str, int, float)):
        raise ValueError("quantity type")
    match = re.fullmatch(
        "([+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?)([numkKMGTPE]|[KMGTPE]i)?",
        str(value),
    )
    if not match:
        raise ValueError("quantity syntax")
    number, suffix = match.groups()
    scales = {
        "": Decimal(1),
        "n": Decimal("1e-9"),
        "u": Decimal("1e-6"),
        "m": Decimal("1e-3"),
        "k": Decimal("1e3"),
        "K": Decimal("1e3"),
    }
    for index, letter in enumerate("MGTPE", 2):
        scales[letter] = Decimal(1000) ** index
    for index, letter in enumerate("KMGTPE", 1):
        scales[letter + "i"] = Decimal(1024) ** index
    return Decimal(number) * scales[suffix or ""]


def _quantity_unicode_finite(value):
    if isinstance(value, bool):
        raise ValueError("quantity")
    match = re.fullmatch(
        "([+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?)([numkKMGTPE]|[KMGTPE]i)?",
        str(value),
    )
    if not match:
        raise ValueError("quantity")
    scales = {
        "n": Decimal("1e-9"),
        "u": Decimal("1e-6"),
        "m": Decimal("1e-3"),
        "k": Decimal("1e3"),
        "K": Decimal("1e3"),
        "M": Decimal("1e6"),
        "G": Decimal("1e9"),
        "T": Decimal("1e12"),
        "P": Decimal("1e15"),
        "E": Decimal("1e18"),
    }
    suffix = match[2] or ""
    factor = (
        Decimal(2) ** (10 * ("KMGTPE".index(suffix[0]) + 1))
        if suffix.endswith("i")
        else scales.get(suffix, Decimal(1))
    )
    amount = Decimal(match[1]) * factor
    if not amount.is_finite():
        raise ValueError("quantity")
    return amount


def _quantity_coerced_ascii(value):
    if isinstance(value, bool):
        raise ValueError("quantity")
    match = re.fullmatch(
        "([+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?)([numkKMGTPE]|[KMGTPE]i)?",
        str(value),
    )
    if not match:
        raise ValueError("quantity")
    suffix = match[2] or ""
    factors = {
        "": 1,
        "n": Decimal("1e-9"),
        "u": Decimal("1e-6"),
        "m": Decimal("1e-3"),
        "k": 1000,
        "K": 1000,
    }
    for i, s in enumerate("MGTPE", 2):
        factors[s] = 1000**i
    for i, s in enumerate("KMGTPE", 1):
        factors[s + "i"] = 1024**i
    return Decimal(match[1]) * factors[suffix]


def quantity(value, *, dialect="typed_ascii"):
    """Parse quantities with the exact 034, 068/095 or 130 input policy."""
    parsers = {
        "typed_ascii": _quantity_typed_ascii,
        "unicode_finite": _quantity_unicode_finite,
        "coerced_ascii": _quantity_coerced_ascii,
    }
    if dialect not in parsers:
        raise ValueError("quantity dialect")
    return parsers[dialect](value)


def _pdb_selector(labels, selector):
    if not isinstance(selector, dict):
        return False
    if not all(
        (labels.get(k) == v for k, v in selector.get("matchLabels", {}).items())
    ):
        return False
    for clause in selector.get("matchExpressions", []):
        key = clause["key"]
        operator = clause["operator"]
        values = clause.get("values", [])
        if operator == "In":
            ok = key in labels and labels[key] in values
        elif operator == "NotIn":
            ok = key not in labels or labels[key] not in values
        elif operator == "Exists":
            ok = key in labels
        elif operator == "DoesNotExist":
            ok = key not in labels
        else:
            return False
        if not ok:
            return False
    return True


def _policy_selector_optional(selector, labels):
    if not isinstance(selector, dict) or set(selector) - {
        "matchLabels",
        "matchExpressions",
    }:
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


def _policy_selector_required(selector, labels):
    if not isinstance(selector, dict) or set(selector) - {
        "matchLabels",
        "matchExpressions",
    }:
        raise ValueError("selector")
    if any((labels.get(k) != v for k, v in selector.get("matchLabels", {}).items())):
        return False
    for e in selector.get("matchExpressions", []):
        k, op, values = (e["key"], e["operator"], e.get("values", []))
        if op == "In":
            good = k in labels and labels[k] in values
        elif op == "NotIn":
            good = k not in labels or labels[k] not in values
        elif op == "Exists":
            good = k in labels
        elif op == "DoesNotExist":
            good = k not in labels
        else:
            raise ValueError("selector operator")
        if not good:
            return False
    return True


def selector_matches(labels, selector, *, dialect="pdb"):
    """Match current labels, preserving PDB and both policy error dialects."""
    if dialect == "pdb":
        return _pdb_selector(labels, selector)
    if dialect == "policy_optional":
        return _policy_selector_optional(selector, labels)
    if dialect == "policy_required":
        return _policy_selector_required(selector, labels)
    raise ValueError("selector dialect")


def selector_equivalent(value, labels):
    """Logical equivalence to an exact fixed label identity (062/119/121)."""
    if not isinstance(value, dict) or set(value) - {"matchLabels", "matchExpressions"}:
        return False
    matches = value.get("matchLabels", {})
    clauses = value.get("matchExpressions", [])
    if not isinstance(matches, dict) or not isinstance(clauses, list):
        return False
    if set(matches) - set(labels) or any((e.get("key") not in labels for e in clauses)):
        return False
    for key, expected in labels.items():
        allowed = {matches[key]} if key in matches else None
        exclusions = set()
        exists = key in matches
        for clause in clauses:
            if clause["key"] != key:
                continue
            operator = clause.get("operator")
            values = clause.get("values", [])
            if operator == "In":
                if not values:
                    return False
                allowed = set(values) if allowed is None else allowed & set(values)
                exists = True
            elif operator == "NotIn":
                exclusions.update(values)
            elif operator == "Exists":
                exists = True
            else:
                return False
        if allowed is None or not exists or allowed - exclusions != {expected}:
            return False
    return True


def named(items, name, *, error="application container identity"):
    """Exactly one named mapping; ignore non-mappings as in 027/042/049."""
    found = [
        item
        for item in items or []
        if isinstance(item, dict) and item.get("name") == name
    ]
    if len(found) != 1:
        raise ValueError(error)
    return found[0]


def workload_worker(document, *, error="worker identity", ignore_non_mappings=False):
    """Strict workload path; choose the original strict or named-list policy."""
    containers = document["spec"]["template"]["spec"]["containers"]
    if ignore_non_mappings:
        return named(containers, "worker", error=error)
    found = [container for container in containers if container.get("name") == "worker"]
    if len(found) != 1:
        raise ValueError(error)
    return found[0]


def optional_pod_worker(pod):
    items = [
        c
        for c in pod.get("spec", {}).get("containers", [])
        if c.get("name") == "worker"
    ]
    return items[0] if len(items) == 1 else {}


def pod_worker(pod):
    return named(pod.get("spec", {}).get("containers", []), "worker")


def current_pods(deployment, replicasets, pods):
    """Current nonterminal Pods owned through controller Deployment/ReplicaSet UIDs."""
    uid = deployment["metadata"]["uid"]
    if not isinstance(uid, str) or not uid:
        raise ValueError("deployment identity")
    owners = {
        rs["metadata"]["uid"]
        for rs in replicasets.get("items", [])
        if any(
            (
                ref.get("kind") == "Deployment"
                and ref.get("uid") == uid
                and (ref.get("controller") is True)
                for ref in rs.get("metadata", {}).get("ownerReferences", [])
            )
        )
    }
    return [
        pod
        for pod in pods.get("items", [])
        if pod.get("metadata", {}).get("deletionTimestamp") is None
        and pod.get("status", {}).get("phase") not in ("Failed", "Succeeded")
        and any(
            (
                ref.get("kind") == "ReplicaSet"
                and ref.get("uid") in owners
                and (ref.get("controller") is True)
                for ref in pod.get("metadata", {}).get("ownerReferences", [])
            )
        )
    ]


def _ready_image_raw(pod, image):
    worker = pod_worker(pod)
    status = named(pod.get("status", {}).get("containerStatuses", []), "worker")
    digest = image.rsplit("@", 1)[-1]
    actual = re.search("(?:^|[@/])(sha256:[0-9a-f]{64})$", status.get("imageID", ""))
    return (
        pod.get("status", {}).get("phase") == "Running"
        and worker.get("image") == image
        and (status.get("ready") is True)
        and isinstance(status.get("state", {}).get("running"), dict)
        and (re.fullmatch("sha256:[0-9a-f]{64}", digest) is not None)
        and (actual is not None)
        and (actual.group(1) == digest)
    )


def ready_image(pod, image):
    """Fail-closed ready worker with a running state and matching immutable image digest."""
    try:
        return _ready_image_raw(pod, image)
    except Exception:
        return False


def read_argument(value):
    """Read one shell here-string via /dev/fd; remove exactly one appended newline."""
    if value.startswith("/dev/fd/"):
        with open(value, encoding="utf-8", newline="") as stream:
            return stream.read().removesuffix("\n")
    return value


def pdb_amount(value, count):
    if type(value) is int and value >= 0:
        return value
    if isinstance(value, str) and re.fullmatch("[0-9]+%", value):
        return (int(value[:-1]) * count + 99) // 100
    raise ValueError("budget")


def pdb_minimum(spec, replicas):
    """Exactly one budget field; round percentages up as in 077/085."""
    if ("minAvailable" in spec) == ("maxUnavailable" in spec):
        raise ValueError("exclusive budget")
    return (
        pdb_amount(spec["minAvailable"], replicas)
        if "minAvailable" in spec
        else replicas - pdb_amount(spec["maxUnavailable"], replicas)
    )


def env_values(values):
    result = {}
    for entry in values or []:
        name = entry["name"]
        if entry.get("valueFrom"):
            ref = entry["valueFrom"]
            choices = [
                key
                for key in (
                    "secretKeyRef",
                    "configMapKeyRef",
                    "fieldRef",
                    "resourceFieldRef",
                )
                if ref.get(key) is not None
            ]
            if len(choices) != 1:
                raise ValueError("environment reference")
            kind = choices[0]
            item = ref[kind]
            if kind in ("secretKeyRef", "configMapKeyRef"):
                result[name] = (kind, item.get("name"), item.get("key"))
            elif kind == "fieldRef":
                result[name] = (
                    kind,
                    item.get("apiVersion") or "v1",
                    item.get("fieldPath"),
                )
            else:
                result[name] = (
                    kind,
                    item.get("containerName") or "",
                    item.get("resource"),
                    _quantity_unicode_finite(item.get("divisor") or "1"),
                )
        else:
            result[name] = ("value", entry.get("value") or "")
    return result


def resource_subset(reference, current, path=(), ignore_behavior=False):
    if path[-3:-1] in (("resources", "requests"), ("resources", "limits")):
        try:
            return _quantity_unicode_finite(reference) == _quantity_unicode_finite(
                current
            )
        except Exception:
            return False
    if isinstance(reference, dict):
        if not isinstance(current, dict):
            return False
        for key, value in reference.items():
            if ignore_behavior and key in (
                "command",
                "args",
                "readinessProbe",
                "livenessProbe",
                "startupProbe",
            ):
                continue
            if key not in current or not resource_subset(
                value, current[key], path + (key,), ignore_behavior
            ):
                return False
        return True
    if isinstance(reference, list):
        if not isinstance(current, list):
            return False
        if path[-1:] in (("drop",),):
            return set(reference) <= set(current)
        if all(
            (
                isinstance(item, dict) and isinstance(item.get("name"), str)
                for item in reference
            )
        ):
            for item in reference:
                matches = [
                    candidate
                    for candidate in current
                    if isinstance(candidate, dict)
                    and candidate.get("name") == item["name"]
                ]
                if len(matches) != 1 or not resource_subset(
                    item, matches[0], path + (item["name"],), ignore_behavior
                ):
                    return False
            return True
        return reference == current
    return type(reference) is type(current) and reference == current


def _health_port(value, container):
    if type(value) is int and 0 < value < 65536:
        return value
    if isinstance(value, str):
        values = [
            item.get("containerPort")
            for item in container.get("ports", [])
            if item.get("name") == value
        ]
        if len(values) == 1 and type(values[0]) is int:
            return values[0]
    raise ValueError("health listener")


def health_probe(container, field="readinessProbe"):
    value = container.get(field)
    if value is None:
        return None
    handlers = [
        name
        for name in ("httpGet", "tcpSocket", "exec", "grpc")
        if value.get(name) is not None
    ]
    if len(handlers) != 1:
        raise ValueError("readiness handler")
    kind = handlers[0]
    handler = value[kind]
    if kind == "httpGet":
        request = (
            kind,
            handler.get("host") or "",
            handler.get("path") or "/",
            handler.get("scheme") or "HTTP",
            _health_port(handler["port"], container),
            tuple(
                (
                    (h.get("name", "").lower(), h.get("value", ""))
                    for h in handler.get("httpHeaders", [])
                )
            ),
        )
    elif kind == "tcpSocket":
        request = (
            kind,
            handler.get("host") or "",
            _health_port(handler["port"], container),
        )
    elif kind == "exec":
        request = (kind, tuple(handler.get("command", [])))
    else:
        request = (
            kind,
            _health_port(handler["port"], container),
            handler.get("service") or "",
        )
    defaults = {
        "initialDelaySeconds": 0,
        "timeoutSeconds": 1,
        "periodSeconds": 10,
        "successThreshold": 1,
        "failureThreshold": 3,
    }
    timing = tuple((value.get(key) or default for key, default in defaults.items()))
    return (request, timing)


def ansible_count(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int) and value >= 0:
        return value
    if isinstance(value, str) and re.fullmatch("[0-9]+", value):
        return int(value)
    return None


def _unique_counter_fields(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise RuntimeError("Ambiguous recap field")
        result[key] = value
    return result


def ansible_recap(text):
    """Parse existing JSON/runner/text recap forms without masking ambiguous fields."""
    records = []
    try:
        records.append(json.loads(text, object_pairs_hook=_unique_counter_fields))
    except ValueError:
        for line in text.splitlines():
            try:
                records.append(
                    json.loads(line, object_pairs_hook=_unique_counter_fields)
                )
            except ValueError:
                pass
    for record in reversed(records):
        if not isinstance(record, dict):
            continue
        stats = record.get("stats")
        if record.get("event") == "playbook_on_stats":
            event = record.get("event_data", {})
            if isinstance(event, dict):
                stats = {
                    host: {
                        key: values.get(host)
                        for key, values in event.items()
                        if isinstance(values, dict)
                    }
                    for host in event.get("processed", {})
                }
        if isinstance(stats, dict):
            rows = {}
            for host, values in stats.items():
                if not isinstance(values, dict):
                    continue
                row = {}
                for key, value in values.items():
                    key = {"failures": "failed", "dark": "unreachable"}.get(key, key)
                    if key in row:
                        raise RuntimeError("Ambiguous normalized recap field")
                    row[key] = ansible_count(value)
                rows[host] = row
            return rows
    rows = {}
    body = text.rsplit("PLAY RECAP", 1)[-1]
    for line in body.splitlines():
        match = re.match("^([^\\s:]+)\\s*:\\s*(.*)$", line)
        if not match:
            continue
        fields = re.findall(
            "\\b(ok|changed|unreachable|failed|skipped|rescued|ignored)\\s*=\\s*([0-9]+)(?=\\s|$)",
            match[2],
        )
        if fields:
            if match[1] in rows or len({key for key, _ in fields}) != len(fields):
                return {}
            rows[match[1]] = {key: int(value) for key, value in fields}
    return rows


def _recaps_by_counter(path, required, positive=(), prefix="recap"):
    try:
        text = Path(path).read_text()
    except OSError:
        text = ""
    rows = ansible_recap(text)
    failed = False
    for number in (1, 2, 3):
        row = rows.get("app" + str(number), {})
        for key, expected in required.items():
            if key == "unreachable" and (not row):
                continue
            if row.get(key) != expected:
                marker = (
                    prefix + "_" + str(number) + "_" + key
                    if key in ("changed", "failed")
                    else "rerun"
                )
                print(
                    "app"
                    + str(number)
                    + " second delivery counter "
                    + key
                    + " must equal "
                    + str(expected)
                    + ": ✗ [DQ:"
                    + marker
                    + "]"
                )
                failed = True
    assert not failed, "Every required managed host needs its own successful recap"


def _recaps_by_host(path, required, positive=(), prefix="recap"):
    try:
        text = Path(path).read_text()
    except OSError:
        text = ""
    rows = ansible_recap(text)
    failed = False
    for number in (1, 2, 3):
        row = rows.get("app" + str(number), {})
        ok = all((row.get(key) == value for key, value in required.items()))
        ok = ok and all(
            (isinstance(row.get(key), int) and row[key] > 0 for key in positive)
        )
        if not ok:
            print(
                "app"
                + str(number)
                + " recap does not satisfy the required counters: ✗ [DQ:"
                + prefix
                + "_"
                + str(number)
                + "]"
            )
            failed = True
    assert not failed, "Every required managed host needs its own successful recap"


def _recaps_shared_marker(path, required, positive=(), prefix="recap"):
    try:
        text = Path(path).read_text()
    except OSError:
        text = ""
    rows = ansible_recap(text)
    failed = False
    for number in (1, 2, 3):
        row = rows.get("app" + str(number), {})
        ok = all((row.get(key) == value for key, value in required.items()))
        ok = ok and all(
            (isinstance(row.get(key), int) and row[key] > 0 for key in positive)
        )
        if not ok:
            print(
                "app"
                + str(number)
                + " recap does not satisfy the required counters: ✗ [DQ:"
                + prefix
                + "]"
            )
            failed = True
    assert not failed, "Every required managed host needs its own successful recap"


def require_recaps(path, required, positive=(), prefix="recap", *, dialect="by_host"):
    """Preserve 020 counter, 025/035/079 host, or 074 shared diagnostic markers."""
    validators = {
        "by_counter": _recaps_by_counter,
        "by_host": _recaps_by_host,
        "shared_marker": _recaps_shared_marker,
    }
    if dialect not in validators:
        raise ValueError("recap dialect")
    return validators[dialect](path, required, positive, prefix)


def resource_records(document, section="values"):
    if not isinstance(document, dict):
        return []
    values = document.get(section)
    root = values.get("root_module") if isinstance(values, dict) else None
    if not isinstance(root, dict):
        return []
    records = []
    pending = [root]
    while pending:
        module = pending.pop()
        resources = module.get("resources") or []
        children = module.get("child_modules") or []
        if not isinstance(resources, list) or not isinstance(children, list):
            return []
        for resource in resources:
            if not isinstance(resource, dict):
                return []
            records.append((module.get("address"), resource))
        if not all((isinstance(child, dict) for child in children)):
            return []
        pending.extend(children)
    return records


def same_target(value, expected, existing=False):
    if not isinstance(value, str) or not value:
        return False
    try:
        expanded = os.path.expanduser(value)
        parent, leaf = os.path.split(expanded)
        if leaf in ("", ".", ".."):
            return False
        if not stat.S_ISDIR(os.stat(parent or ".").st_mode):
            return False
        target = Path(expected)
        if existing or target.exists():
            if not stat.S_ISREG(os.stat(expanded).st_mode):
                return False
            return Path(expanded).resolve(strict=True) == target.resolve(strict=True)
        candidate = Path(parent or ".").resolve(strict=True) / leaf
        return candidate == target.parent.resolve(strict=True) / target.name
    except (OSError, RuntimeError, ValueError):
        return False


def file_resources(records, filename, in_module=False):
    found = []
    for module, resource in records:
        values = resource.get("values")
        if (
            resource.get("mode") == "managed"
            and resource.get("type") == "local_file"
            and isinstance(values, dict)
            and same_target(values.get("filename"), filename)
            and (not in_module or (isinstance(module, str) and bool(module)))
        ):
            found.append((module, resource))
    return found


def number_is(value, expected):
    return type(value) in (int, float) and value == expected


def read_json(path, successful=True):
    if not successful:
        return None
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None


def tofu_json(*arguments):
    result = subprocess.run(["tofu", *arguments], capture_output=True, text=True)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except ValueError:
        return None


class UnsupportedForwarder(ValueError):
    """The deliberately limited original HCL forwarder cannot prove this expression."""


def hcl_tokens(source):
    """Tokenize only; strings/comments/heredocs never become declarations."""
    length = len(source)

    def comment(position):
        if source.startswith("/*", position):
            end = source.find("*/", position + 2)
            if end < 0:
                raise UnsupportedForwarder("Unterminated comment")
            return end + 2
        end = source.find("\n", position)
        return length if end < 0 else end

    def heredoc(position):
        end = source.find("\n", position)
        if end < 0:
            raise UnsupportedForwarder("Unterminated heredoc")
        intro = source[position:end].rstrip("\r")
        match = re.fullmatch("<<(-?)([A-Za-z_][A-Za-z0-9_-]*)[ \\t]*", intro)
        if not match:
            raise UnsupportedForwarder("Unsupported heredoc marker")
        indented, marker = match.groups()
        position = end + 1
        while position < length:
            end = source.find("\n", position)
            end = length if end < 0 else end
            line = source[position:end].rstrip("\r")
            if line.strip() == marker:
                if line != marker and (not indented or line.lstrip(" \t") != marker):
                    raise UnsupportedForwarder(
                        "Unsupported heredoc delimiter whitespace"
                    )
                return end
            position = end + 1
        raise UnsupportedForwarder("Unterminated heredoc")

    def quoted(position):
        position += 1
        while position < length:
            if source[position] == "\\":
                position += 2
            elif source.startswith(("$${", "%%{"), position):
                position += 3
            elif source.startswith(("${", "%{"), position):
                position = interpolation(position + 2)
            elif source[position] == '"':
                return position + 1
            else:
                position += 1
        raise UnsupportedForwarder("Unterminated string")

    def interpolation(position):
        depth = 1
        while position < length:
            if source[position] == '"':
                position = quoted(position)
            elif source[position] == "#" or source.startswith(("//", "/*"), position):
                position = comment(position)
            elif source.startswith("<<", position):
                position = heredoc(position)
            elif source[position] == "{":
                depth += 1
                position += 1
            elif source[position] == "}":
                depth -= 1
                position += 1
                if not depth:
                    return position
            else:
                position += 1
        raise UnsupportedForwarder("Unterminated interpolation")

    tokens = []
    position = 0
    while position < length:
        character = source[position]
        if character in " \t\r":
            position += 1
        elif character == "\n":
            tokens.append(("newline", "\n"))
            position += 1
        elif character == "#" or source.startswith(("//", "/*"), position):
            position = comment(position)
        elif character == '"':
            end = quoted(position)
            tokens.append(("string", source[position:end]))
            position = end
        elif source.startswith("<<", position):
            end = heredoc(position)
            tokens.append(("opaque", source[position:end]))
            position = end
        elif character.isalpha() or character == "_":
            end = position + 1
            while end < length and (source[end].isalnum() or source[end] in "_-"):
                end += 1
            tokens.append(("word", source[position:end]))
            position = end
        else:
            tokens.append(("punctuation", character))
            position += 1
    return tokens


def block_attributes(tokens):
    attributes = {}
    position = 0
    while position < len(tokens):
        if tokens[position][0] == "newline":
            position += 1
            continue
        if (
            position + 1 >= len(tokens)
            or tokens[position][0] != "word"
            or tokens[position + 1][1] != "="
        ):
            raise UnsupportedForwarder("Unsupported block declaration")
        name = tokens[position][1]
        position += 2
        start = position
        depth = 0
        while position < len(tokens):
            text = tokens[position][1]
            if tokens[position][0] == "newline" and (not depth):
                break
            if text in ("(", "[", "{"):
                depth += 1
            elif text in (")", "]", "}"):
                depth -= 1
                if depth < 0:
                    raise UnsupportedForwarder("Unbalanced expression")
            position += 1
        if name in attributes:
            raise UnsupportedForwarder("Duplicate attribute")
        attributes[name] = tokens[start:position]
    return attributes


def forward_reference(tokens):
    """Accept only transparent forwarding, never an unused conditional ref."""
    tokens = [token for token in tokens if token[0] != "newline"]
    position = 0
    wrappers = {"trimspace", "chomp", "tostring", "sensitive", "nonsensitive"}

    def expression():
        nonlocal position
        if position >= len(tokens):
            raise UnsupportedForwarder("Missing expression")
        kind, text = tokens[position]
        if text == "(":
            position += 1
            result = expression()
            if position >= len(tokens) or tokens[position][1] != ")":
                raise UnsupportedForwarder("Missing parenthesis")
            position += 1
            return result
        if kind == "string":
            position += 1
            if not (text.startswith('"${') and text.endswith('}"')):
                raise UnsupportedForwarder("Literal is not a reference")
            return forward_reference(hcl_tokens(text[3:-2]))
        if kind != "word":
            raise UnsupportedForwarder("Not a forwarding expression")
        position += 1
        if position < len(tokens) and tokens[position][1] == "(":
            if text not in wrappers:
                raise UnsupportedForwarder("Opaque function")
            position += 1
            result = expression()
            if position >= len(tokens) or tokens[position][1] != ")":
                raise UnsupportedForwarder("Not a unary transparent wrapper")
            position += 1
            return result
        result = text
        while position < len(tokens):
            if tokens[position][1] == ".":
                position += 1
                if position >= len(tokens) or tokens[position][0] != "word":
                    raise UnsupportedForwarder("Invalid traversal")
                result += "." + tokens[position][1]
                position += 1
            elif tokens[position][1] == "[":
                position += 1
                if position >= len(tokens):
                    raise UnsupportedForwarder("Missing lookup index")
                if tokens[position][0] == "string":
                    name = json.loads(tokens[position][1])
                    if not isinstance(name, str):
                        raise UnsupportedForwarder("Invalid lookup name")
                    if result == "local" and re.fullmatch(
                        "[A-Za-z_][A-Za-z0-9_-]*", name
                    ):
                        result += "." + name
                    else:
                        result += "[" + json.dumps(name, ensure_ascii=False) + "]"
                    position += 1
                else:
                    digits = ""
                    while position < len(tokens) and re.fullmatch(
                        "[0-9]", tokens[position][1]
                    ):
                        digits += tokens[position][1]
                        position += 1
                    if not digits:
                        raise UnsupportedForwarder(
                            "Only literal instance indices are certified"
                        )
                    result += "[" + str(int(digits)) + "]"
                if position >= len(tokens) or tokens[position][1] != "]":
                    raise UnsupportedForwarder("Invalid lookup")
                position += 1
            else:
                break
        return result

    result = expression()
    if position != len(tokens):
        raise UnsupportedForwarder("Opaque expression")
    return result


def _forward_definitions(directory, output_name, block_kind, attribute):
    local_values = {}
    output = None

    def add_local(name, value):
        if name in local_values:
            raise UnsupportedForwarder("Duplicate local definition")
        local_values[name] = value

    def json_expression(value):
        if isinstance(value, str) and value.startswith("${") and value.endswith("}"):
            return hcl_tokens(value[2:-1])
        raise UnsupportedForwarder("Not an expression template")

    for path in sorted(Path(directory).iterdir()):
        if path.name.startswith((".", "#")) or path.name.endswith("~"):
            continue
        if path.name.endswith(".tf.json"):
            data = json.loads(path.read_text())
            blocks = data.get("locals", [])
            blocks = [blocks] if isinstance(blocks, dict) else blocks
            for block in blocks:
                for name, value in block.items():
                    try:
                        add_local(name, json_expression(value))
                    except UnsupportedForwarder:
                        add_local(name, [("opaque", "")])
            block = data.get(block_kind, {}).get(output_name)
            if block is not None:
                if output is not None:
                    raise UnsupportedForwarder("Duplicate output")
                output = json_expression(block[attribute])
        elif path.name.endswith(".tf"):
            tokens = hcl_tokens(path.read_text())
            position = 0
            while position < len(tokens):
                if tokens[position][0] == "newline":
                    position += 1
                    continue
                start = position
                while position < len(tokens) and tokens[position][1] != "{":
                    position += 1
                if position == len(tokens):
                    raise UnsupportedForwarder("Incomplete top-level block")
                header = [
                    token for token in tokens[start:position] if token[0] != "newline"
                ]
                position += 1
                body_start = position
                depth = 1
                while position < len(tokens) and depth:
                    if tokens[position][1] == "{":
                        depth += 1
                    elif tokens[position][1] == "}":
                        depth -= 1
                    position += 1
                if depth:
                    raise UnsupportedForwarder("Unterminated block")
                body = tokens[body_start : position - 1]
                if header == [("word", "locals")]:
                    for name, value in block_attributes(body).items():
                        add_local(name, value)
                elif (
                    len(header) == 2
                    and header[0] == ("word", block_kind)
                    and (
                        header[1][0] == "string"
                        and json.loads(header[1][1]) == output_name
                        or header[1] == ("word", output_name)
                    )
                ):
                    if output is not None:
                        raise UnsupportedForwarder("Duplicate output")
                    output = block_attributes(body)[attribute]
    if output is None:
        raise UnsupportedForwarder("Missing output definition")
    return (output, local_values)


_DEFAULT_OUTPUT = object()


def module_forwards(
    directory, references, endpoint, output_name=_DEFAULT_OUTPUT, *, dialect="module"
):
    """064 module/region (station) or 098 output/value (route), without HCL evaluation."""
    if dialect not in ("module", "output"):
        raise ValueError("forwarder dialect")
    if output_name is _DEFAULT_OUTPUT:
        output_name = "station" if dialect == "module" else "route"
    try:
        expression, definitions = _forward_definitions(
            directory,
            output_name,
            dialect,
            "region" if dialect == "module" else "value",
        )
        reference = forward_reference(expression)
        known = {
            forward_reference(hcl_tokens(value))
            for value in references
            if isinstance(value, str)
        }
        if reference not in known:
            return False
        endpoint = forward_reference(hcl_tokens(endpoint))
        seen = set()
        while reference != endpoint:
            if not reference.startswith("local.") or reference.count(".") != 1:
                return False
            name = reference.split(".", 1)[1]
            if name in seen or name not in definitions:
                return False
            seen.add(name)
            reference = forward_reference(definitions[name])
        return True
    except (OSError, ValueError, KeyError, TypeError):
        return False


# Additional primitives required by the remaining check migrations.


def credential_fields(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate credential field")
        result[key] = value
    return result


def registry_credentials(secret, registry, user, password):
    """Validate the original exact registry entry and either Docker credential format."""
    kind = secret.get("type")
    key = (
        ".dockerconfigjson"
        if kind == "kubernetes.io/dockerconfigjson"
        else ".dockercfg"
        if kind == "kubernetes.io/dockercfg"
        else None
    )
    if key is None:
        return False
    value = json.loads(
        base64.b64decode(secret["data"][key], validate=True),
        object_pairs_hook=credential_fields,
    )
    auths = value.get("auths") if key == ".dockerconfigjson" else value
    if not isinstance(auths, dict):
        return False
    entry = auths.get(registry)
    if not isinstance(entry, dict):
        return False
    auth = entry.get("auth")
    if auth not in (None, ""):
        return (
            isinstance(auth, str)
            and base64.b64decode(
                auth.replace("\r", "").replace("\n", ""), validate=True
            )
            == (user + ":" + password).encode()
        )
    return entry.get("username") == user and entry.get("password") == password


def pull_secret_names(pod):
    names = set()
    for entry in pod.get("spec", {}).get("imagePullSecrets") or []:
        value = entry.get("name")
        if not isinstance(value, str) or not re.fullmatch(
            "[a-z0-9](?:[-a-z0-9.]*[a-z0-9])?", value
        ):
            raise ValueError("pull credential identity")
        names.add(value)
    return names


def port_number(containers, value, protocol="TCP"):
    """Resolve exact numeric or uniquely named workload ports, preserving protocol filtering."""
    if type(value) is int:
        return value
    if not isinstance(value, str) or not value:
        raise ValueError("named port")
    found = {
        p["containerPort"]
        for c in containers
        for p in c.get("ports", [])
        if p.get("name") == value and p.get("protocol", "TCP") == protocol
    }
    if len(found) != 1:
        raise ValueError("named port")
    return found.pop()


def _readiness_port(container, value):
    if type(value) is int:
        return value
    if not isinstance(value, str):
        raise ValueError("port")
    found = [
        p["containerPort"] for p in container.get("ports", []) if p.get("name") == value
    ]
    if len(found) != 1 or type(found[0]) is not int:
        raise ValueError("named port")
    return found[0]


def _readiness_worker(document):
    return workload_worker(document, error="worker")


def readiness_probe(document, tcp=False):
    """067/102 HTTP readiness, optionally TCP; retain their unbounded direct integer port policy."""
    container = _readiness_worker(document)
    probe = container.get("readinessProbe", {})
    kinds = [
        name
        for name in ("httpGet", "tcpSocket", "exec", "grpc")
        if probe.get(name) is not None
    ]
    if len(kinds) != 1 or kinds[0] not in (
        ["httpGet", "tcpSocket"] if tcp else ["httpGet"]
    ):
        return False
    action = probe[kinds[0]]
    if action.get("host", "") != "":
        return False
    if kinds[0] == "httpGet" and action.get("scheme", "HTTP") != "HTTP":
        return False
    return _readiness_port(container, action.get("port")) == 8080


def _health_worker(document):
    return workload_worker(document, error="application worker identity")


def workload_agreement(desired, live):
    left, right = (_health_worker(desired), _health_worker(live))
    if left.get("image") != right.get("image"):
        return False
    if (left.get("command") or []) != (right.get("command") or []) or (
        left.get("args") or []
    ) != (right.get("args") or []):
        return False
    if env_values(left.get("env")) != env_values(right.get("env")):
        return False
    return all(
        (
            health_probe(left, field) == health_probe(right, field)
            for field in ("readinessProbe", "livenessProbe", "startupProbe")
        )
    )


def workload_safety(reference, current):
    old = reference["spec"]["template"]["spec"]
    new = current["spec"]["template"]["spec"]
    base = _health_worker(reference)
    actual = _health_worker(current)
    old_pod = old.get("securityContext", {})
    new_pod = new.get("securityContext", {})
    for field in ("runAsUser", "runAsGroup", "runAsNonRoot", "seccompProfile"):
        expected = base.get("securityContext", {}).get(field, old_pod.get(field))
        observed = actual.get("securityContext", {}).get(field, new_pod.get(field))
        if expected is not None and expected != observed:
            return False
    for field in ("hostNetwork", "hostPID", "hostIPC"):
        if bool(new.get(field)) != bool(old.get(field)):
            return False
    for container in new.get("containers", []) + new.get("initContainers", []):
        context = container.get("securityContext", {})
        if (
            context.get("privileged", False)
            or context.get("allowPrivilegeEscalation") is not False
        ):
            return False
        if "ALL" not in context.get("capabilities", {}).get("drop", []) or context.get(
            "capabilities", {}
        ).get("add"):
            return False
        uid = context.get("runAsUser", new_pod.get("runAsUser"))
        nonroot = context.get("runAsNonRoot", new_pod.get("runAsNonRoot"))
        if uid == 0 or not (nonroot is True or (type(uid) is int and uid > 0)):
            return False
    return True


def selector_implies(selector, required):
    """Prove exact required identities and satisfiability of label conjunctions."""
    if not isinstance(selector, dict) or set(selector) - {
        "matchLabels",
        "matchExpressions",
    }:
        return False
    allowed = {k: {v} for k, v in selector.get("matchLabels", {}).items()}
    present = set(allowed)
    absent = set()
    excluded = {}
    for e in selector.get("matchExpressions", []):
        k, op, vs = (e.get("key"), e.get("operator"), set(e.get("values", [])))
        if op == "In":
            present.add(k)
            allowed[k] = allowed.get(k, vs) & vs
        elif op == "NotIn":
            excluded.setdefault(k, set()).update(vs)
        elif op == "DoesNotExist":
            absent.add(k)
        elif op == "Exists":
            present.add(k)
        else:
            return False
    if present & absent:
        return False
    for k in allowed:
        allowed[k] -= excluded.get(k, set())
    return all((allowed.get(k) == {v} for k, v in required.items())) and all(
        (v for v in allowed.values())
    )


def capability_list(context, key):
    value = context.get("capabilities", {}) or {}
    if not isinstance(value, dict):
        return None
    result = value.get(key, []) or []
    return result if isinstance(result, list) else None


def seccomp_profile(context):
    value = context.get("seccompProfile")
    if value is None:
        return None
    return value.get("type", "invalid") if isinstance(value, dict) else "invalid"


def positive_user_ids(policy, contexts):
    return all(
        (
            type(v) is int and v > 0
            for c in [policy] + contexts
            for v in [c.get("runAsUser")]
            if v is not None
        )
    )


def nonroot_policy(policy, contexts):
    no_false = all(
        (
            c.get("runAsNonRoot") in (None, True) and c.get("runAsNonRoot") is not False
            for c in [policy] + contexts
        )
    )
    inherited = all(
        (
            (
                c.get("runAsNonRoot")
                if c.get("runAsNonRoot") is not None
                else policy.get("runAsNonRoot")
            )
            is True
            for c in contexts
        )
    )
    return no_false and inherited and positive_user_ids(policy, contexts)


def runtime_default_policy(policy, contexts):
    return all(
        (seccomp_profile(c) in (None, "RuntimeDefault") for c in [policy] + contexts)
    ) and all(
        (
            (seccomp_profile(c) or seccomp_profile(policy)) == "RuntimeDefault"
            for c in contexts
        )
    )


def readonly_mount(mount, by_name):
    source = by_name[mount["name"]]
    if mount.get("readOnly") is True:
        return True
    if any(
        (
            source.get(key) is not None
            for key in ("configMap", "secret", "projected", "downwardAPI")
        )
    ):
        return True
    return any(
        (
            isinstance(source.get(key), dict) and source[key].get("readOnly") is True
            for key in ("persistentVolumeClaim", "csi")
        )
    )
