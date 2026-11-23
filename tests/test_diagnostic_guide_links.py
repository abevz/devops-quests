"""Condition explanations link to named sections in the public guide."""

import ast
from pathlib import Path
import re

import pytest

from devops_quests.catalog import Catalog

GUIDE_LINK = re.compile(
    r"\[[^\]\n]+\]\(guides#guide=([a-z0-9.-]+)&section=([a-z][a-z0-9-]*)\)"
)
SECTION = re.compile(r"^#{2,6}[ \t]+.+[ \t]+\{#([a-z][a-z0-9-]*)\}[ \t]*$", re.M)
MARKER = re.compile(r"\[DQ:([a-z0-9_]+)\]")
FLEET_MARKER = re.compile(r"\[DQ:([a-z0-9_]+)\$(?:n|host)\]")


@pytest.fixture(scope="module")
def catalog():
    return Catalog()


@pytest.mark.parametrize("quest", range(1, 131))
def test_each_migrated_condition_has_a_localized_explanation_and_guide(catalog, quest):
    markers = set()
    for stage in catalog.quests[quest]["stages"]:
        for goal in stage["objectives"]:
            check = goal["check"]
            emitted = set(MARKER.findall(check))
            for _, body in re.findall(r"<<'(DQ_PROPERTY|DQ_RELEASE_BUNDLE|DQ_RELEASE|DQ_MEMORY_BUDGET|DQ_MEMORY_DATA)'\n(.*?)\n\1(?:\n|$)", check, re.S):
                # Source-declared marker arguments; phase reachability is audited
                # against the actual producer/failover checks, not locale keys.
                for node in ast.walk(ast.parse(body)):
                    positions = {"require": 1, "command": 1, "document": 1, "get": 2}
                    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
                        position = positions.get(node.func.id)
                        if position is not None and len(node.args) > position:
                            value = node.args[position]
                            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                                emitted.add(value.value)
                    if isinstance(node, ast.FunctionDef) and node.name == "get":
                        emitted.update(
                            value.value for value in node.args.defaults
                            if isinstance(value, ast.Constant) and isinstance(value.value, str)
                        )
            for body in re.findall(r"<<'DQ_PERFORMANCE'\n(.*?)\nDQ_PERFORMANCE(?:\n|$)", check, re.S):
                tree = ast.parse(body)
                positions = {"require": 1, "command": 1, "document": 1, "get": 2}
                prefixes = set()
                for node in ast.walk(tree):
                    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
                        position = positions.get(node.func.id)
                        if position is not None and len(node.args) > position:
                            value = node.args[position]
                            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                                emitted.add(value.value)
                    if isinstance(node, ast.FunctionDef) and node.name == "get":
                        emitted.update(value.value for value in node.args.defaults
                                       if isinstance(value, ast.Constant) and isinstance(value.value, str))
                    if (isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add)
                            and isinstance(node.left, ast.Constant)
                            and node.left.value in {"performance_consumer_", "performance_progress_"}):
                        suffix = node.right
                        assert isinstance(suffix, ast.Call) and isinstance(suffix.func, ast.Attribute)
                        assert suffix.func.attr == "replace"
                        assert [ast.literal_eval(value) for value in suffix.args] == ["-", "_"]
                        subject = suffix.func.value
                        assert (isinstance(subject, ast.Name) and subject.id == "name") or (
                            isinstance(subject, ast.Subscript) and isinstance(subject.value, ast.Name)
                            and subject.value.id == "consumer" and ast.literal_eval(subject.slice) == "deployment"
                        )
                        prefixes.add(node.left.value)
                if prefixes:
                    setup = (Path("quests") / f"{quest:03}" / "setup-0.sh").read_text()
                    setup_body, = re.findall(r"<<'DQ_DEMAND'\n(.*?)\nDQ_DEMAND(?:\n|$)", setup, re.S)
                    contract, = [node.value for node in ast.walk(ast.parse(setup_body))
                                 if isinstance(node, ast.Assign) and any(
                                     isinstance(target, ast.Name) and target.id == "contract"
                                     for target in node.targets)]
                    consumers, = [value for key, value in zip(contract.keys, contract.values, strict=True)
                                  if isinstance(key, ast.Constant) and key.value == "consumers"]
                    assert isinstance(consumers, ast.ListComp) and len(consumers.generators) == 1
                    generator, = consumers.generators
                    assert isinstance(generator.target, ast.Name) and generator.target.id == "name"
                    deployment, = [value for key, value in zip(consumers.elt.keys, consumers.elt.values, strict=True)
                                   if isinstance(key, ast.Constant) and key.value == "deployment"]
                    assert isinstance(deployment, ast.Name) and deployment.id == "name"
                    names = ast.literal_eval(generator.iter)
                    assert names and all(isinstance(name, str) for name in names)
                    emitted.update(prefix + name.replace("-", "_") for prefix in prefixes for name in names)
            for body in re.findall(r"<<'DQ_ROLLBACK_ADOPTION'\n(.*?)\nDQ_ROLLBACK_ADOPTION(?:\n|$)", check, re.S):
                tree = ast.parse(body)
                calls = [node.args[0] for node in ast.walk(tree)
                         if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                         and node.func.id == "reject" and node.args]
                emitted.update(value.value for value in calls
                               if isinstance(value, ast.Constant) and isinstance(value.value, str))
                identity_loop, = [node for node in ast.walk(tree)
                                  if isinstance(node, ast.For) and isinstance(node.target, ast.Name)
                                  and node.target.id == "name" and isinstance(node.iter, ast.Tuple)]
                names = ast.literal_eval(identity_loop.iter)
                suffix, = [node.value for node in ast.walk(identity_loop)
                           if isinstance(node, ast.Assign) and any(
                               isinstance(target, ast.Name) and target.id == "suffix"
                               for target in node.targets)]
                assert ast.unparse(suffix) == "'board' if name == 'board' else name[-1]"
                identity_suffixes = {name if name == suffix.body.value else name[-1] for name in names}
                setup = (Path(__file__).resolve().parents[1] / f"quests/{quest:03}/setup-0.sh").read_text()
                receipt, = re.findall(r"<<'DQ_ROLLBACK_RECEIPT'\n(.*?)\nDQ_ROLLBACK_RECEIPT(?:\n|$)", setup, re.S)
                lane_loop, = [node for node in ast.walk(ast.parse(receipt))
                              if isinstance(node, ast.For) and isinstance(node.target, ast.Name)
                              and node.target.id == "lane"]
                lanes = ast.literal_eval(lane_loop.iter)
                profiles = [call.args[0] for call in ast.walk(lane_loop)
                            if isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute)
                            and isinstance(call.func.value, ast.Name) and call.func.value.id == "consumers"
                            and call.func.attr == "append"]
                profile, = profiles
                lane, = [value for key, value in zip(profile.keys, profile.values, strict=True)
                         if isinstance(key, ast.Constant) and key.value == "lane"]
                assert isinstance(lane, ast.Name) and lane.id == "lane"
                for value in calls:
                    if not isinstance(value, ast.BinOp):
                        continue
                    assert isinstance(value.op, ast.Add) and isinstance(value.left, ast.Constant)
                    assert isinstance(value.right, ast.Name)
                    prefix = value.left.value
                    if value.right.id == "suffix":
                        assert prefix == "rollback_identity_"
                        emitted.update(prefix + suffix for suffix in identity_suffixes)
                    else:
                        assert value.right.id == "lane" and prefix in {
                            "rollback_source_", "rollback_delivery_", "rollback_http_"
                        }
                        emitted.update(prefix + lane for lane in lanes)
            for body in re.findall(r"<<'DQ_RESTORE_IDENTITY'\n(.*?)\nDQ_RESTORE_IDENTITY(?:\n|$)", check, re.S):
                tree = ast.parse(body)
                host_loop, = [node for node in ast.walk(tree)
                              if isinstance(node, ast.For) and isinstance(node.target, ast.Tuple)
                              and isinstance(node.target.elts[0], ast.Name)
                              and node.target.elts[0].id == "active_index"]
                assert isinstance(host_loop.iter, ast.Call) and host_loop.iter.func.id == "enumerate"
                hosts, start = host_loop.iter.args
                indices = range(ast.literal_eval(start), ast.literal_eval(start) + len(ast.literal_eval(hosts)))
                calls = [node.args[0] for node in ast.walk(tree)
                         if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                         and node.func.id == "reject" and node.args]
                for value in calls:
                    if isinstance(value, ast.Constant):
                        emitted.add(value.value)
                        continue
                    assert isinstance(value, ast.BinOp) and isinstance(value.op, ast.Add)
                    if isinstance(value.left, ast.Name):
                        assert value.left.id == "marker"
                        prefixes = {node.value.value for node in ast.walk(host_loop)
                                    if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant)
                                    and any(isinstance(target, ast.Name) and target.id == "marker"
                                            for target in node.targets)}
                        assert prefixes == {"live_binding_", "live_data_"}
                        emitted.update(prefix + str(index) for prefix in prefixes for index in indices)
                    else:
                        assert isinstance(value.left, ast.Constant)
                        prefix = value.left.value
                        if prefix == "restore_observation":
                            assert isinstance(value.right, ast.IfExp)
                            assert isinstance(value.right.orelse, ast.Constant) and value.right.orelse.value == ""
                            emitted.add(prefix)
                            emitted.update(prefix + "_" + str(index) for index in indices)
                        else:
                            assert prefix in {"application_identity_", "application_ready_"}
                            emitted.update(prefix + str(index) for index in indices)
                caller, = [node.value.value for node in ast.walk(tree)
                           if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant)
                           and any(isinstance(target, ast.Name) and target.id == "caller_program"
                                   for target in node.targets)]
                for call in ast.walk(ast.parse(caller)):
                    if isinstance(call, ast.Call) and isinstance(call.func, ast.Name) and call.func.id == "print":
                        for argument in call.args:
                            if isinstance(argument, ast.Constant) and isinstance(argument.value, str):
                                emitted.update(MARKER.findall(argument.value))
            for delimiter, function, position in (
                ("DQ_HANDOVER", "reject", 0),
                ("DQ_GIT_ACCESS", "reject", 0),
                ("DQ_PUBLICATION", "reject", 0),
                ("DQ_BATCH_POLICY", "require", 1),
                ("DQ_BATCH_POLICY", "get", 2),
                ("DQ_BATCH_EVIDENCE", "require", 1),
                ("DQ_BATCH_EVIDENCE", "get", 2),
                ("DQ_ISOLATION_MEMBERSHIP", "require", 1),
                ("DQ_PROFILE_SCOPE", "require", 1),
                ("DQ_ROLE_CAPABILITY", "require", 1),
            ):
                for body in re.findall(
                    rf"<<'{delimiter}'\n(.*?)\n{delimiter}(?:\n|$)", check, re.S
                ):
                    for call in ast.walk(ast.parse(body)):
                        if (isinstance(call, ast.Call)
                                and isinstance(call.func, ast.Name)
                                and call.func.id == function
                                and len(call.args) > position
                                and isinstance(call.args[position], ast.Constant)
                                and isinstance(call.args[position].value, str)):
                            emitted.add(call.args[position].value)
            for body in re.findall(r"<<'DQ_PUBLICATION'\n(.*?)\nDQ_PUBLICATION(?:\n|$)", check, re.S):
                tree = ast.parse(body)
                dynamic = [
                    call.args[0] for call in ast.walk(tree)
                    if isinstance(call, ast.Call) and isinstance(call.func, ast.Name)
                    and call.func.id == "reject" and call.args
                    and isinstance(call.args[0], ast.BinOp)
                    and isinstance(call.args[0].op, ast.Add)
                    and isinstance(call.args[0].left, ast.Constant)
                    and isinstance(call.args[0].left.value, str)
                ]
                if dynamic:
                    loops = [
                        node for node in ast.walk(tree)
                        if isinstance(node, ast.For) and isinstance(node.target, ast.Tuple)
                        and isinstance(node.target.elts[0], ast.Name)
                        and node.target.elts[0].id == "active_index"
                        and isinstance(node.iter, ast.Call)
                        and isinstance(node.iter.func, ast.Name)
                        and node.iter.func.id == "enumerate"
                    ]
                    loop, = loops
                    hosts, start = loop.iter.args
                    assert isinstance(hosts, ast.Tuple) and isinstance(start, ast.Constant)
                    indices = range(start.value, start.value + len(hosts.elts))
                    for value in dynamic:
                        prefix = value.left.value
                        if prefix.endswith("_"):
                            emitted.update(prefix + str(index) for index in indices)
                        else:
                            # Before the first host, observation errors have no
                            # suffix; after entering a host they include its index.
                            assert prefix == "application_observation"
                            assert isinstance(value.right, ast.IfExp)
                            assert isinstance(value.right.orelse, ast.Constant)
                            assert value.right.orelse.value == ""
                            emitted.add(prefix)
                            emitted.update(prefix + "_" + str(index) for index in indices)
            for _, body in re.findall(
                r"<<'(DQ_MEMORY_BUDGET|DQ_MEMORY_DATA)'\n(.*?)\n\1(?:\n|$)", check, re.S
            ):
                tree = ast.parse(body)
                positions = {"require": 1, "command": 1, "document": 1, "get": 2}
                used = set()
                for call in ast.walk(tree):
                    if isinstance(call, ast.Call) and isinstance(call.func, ast.Name):
                        position = positions.get(call.func.id)
                        if position is not None and len(call.args) > position:
                            value = call.args[position]
                            if isinstance(value, ast.Name):
                                used.add(value.id)
                prefixes = {
                    node.value.left.value for node in ast.walk(tree)
                    if isinstance(node, ast.Assign)
                    and any(isinstance(target, ast.Name) and target.id in used
                            for target in node.targets)
                    and isinstance(node.value, ast.BinOp) and isinstance(node.value.op, ast.Add)
                    and isinstance(node.value.left, ast.Constant)
                    and isinstance(node.value.right, ast.Name) and node.value.right.id == "name"
                }
                if prefixes:
                    setup = (Path(__file__).resolve().parents[1]
                             / f"quests/{quest:03}/setup-0.sh").read_text()
                    seed, = re.findall(
                        r"<<'DQ_STARTUP_SEED'\n(.*?)\nDQ_STARTUP_SEED(?:\n|$)", setup, re.S
                    )
                    contract, = [
                        node.value for node in ast.walk(ast.parse(seed))
                        if isinstance(node, ast.Assign)
                        and any(isinstance(target, ast.Name) and target.id == "contract"
                                for target in node.targets)
                    ]
                    roles, = [
                        value for key, value in zip(contract.keys, contract.values, strict=True)
                        if isinstance(key, ast.Constant) and key.value == "roles"
                    ]
                    names = {role["deployment"] for role in ast.literal_eval(roles)}
                    assert names and all(isinstance(name, str) for name in names)
                    emitted.update(prefix + name for prefix in prefixes for name in names)
            if "[DQ:field_${field,,}]" in check:
                # Quest 072 declares each field assignment at the actual probe.
                # Case arms describe values, not additional emitted fields.
                fields = re.findall(r"^field=([A-Za-z]+)$", check, re.M)
                assert fields
                emitted.update("field_" + field.lower() for field in fields)
            for body in re.findall(
                r"<<'DQ_STORAGE_(?:POLICY|DATA)'\n(.*?)\nDQ_STORAGE_(?:POLICY|DATA)(?:\n|$)",
                check, re.S,
            ):
                tree = ast.parse(body)
                for call in ast.walk(tree):
                    positions = {"require": 1, "command": 1, "get": 2}
                    if isinstance(call, ast.Call) and isinstance(call.func, ast.Name):
                        position = positions.get(call.func.id)
                        if position is not None and len(call.args) > position:
                            value = call.args[position]
                            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                                emitted.add(value.value)
                # Resolve dynamic suffixes from the setup's actual source/target
                # contract, rather than assuming names from the locale mapping.
                setup = (Path(__file__).resolve().parents[1]
                         / f"quests/{quest:03}/setup-0.sh").read_text()
                seed, = re.findall(
                    r"<<'DQ_STORAGE_SEED'\n(.*?)\nDQ_STORAGE_SEED(?:\n|$)", setup, re.S
                )
                contract, = [
                    node.value for node in ast.walk(ast.parse(seed))
                    if isinstance(node, ast.Assign)
                    and any(isinstance(t, ast.Name) and t.id == "contract" for t in node.targets)
                ]
                deployments = set()
                for key, role in zip(contract.keys, contract.values, strict=True):
                    if isinstance(key, ast.Constant) and key.value in ("source", "target"):
                        for field, value in zip(role.keys, role.values, strict=True):
                            if field.value == "deployment":
                                deployments.add(value.value)
                assert len(deployments) == 2
                prefixes = {
                    node.left.value for node in ast.walk(tree)
                    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add)
                    and isinstance(node.left, ast.Constant)
                    and node.left.value in (
                        "storage_mount_", "storage_ready_", "storage_data_", "storage_publication_"
                    )
                }
                emitted.update(prefix + name for prefix in prefixes for name in deployments)
            for body in re.findall(
                r"<<'DQ_CALLER_CAPABILITY'\n(.*?)\nDQ_CALLER_CAPABILITY(?:\n|$)",
                check, re.S,
            ):
                tree = ast.parse(body)
                forwarded = {
                    marker for assignment in ast.walk(tree)
                    if isinstance(assignment, ast.Assign)
                    and any(isinstance(t, ast.Name) and t.id == "markers"
                            for t in assignment.targets)
                    for value in assignment.value.elts
                    for marker in MARKER.findall(value.value)
                }
                producers = [tree]
                for call in ast.walk(tree):
                    if (isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute)
                            and call.func.attr == "run" and call.args
                            and isinstance(call.args[0], ast.List)):
                        arguments = call.args[0].elts
                        for index, argument in enumerate(arguments[:-1]):
                            if isinstance(argument, ast.Constant) and argument.value == "-c":
                                producers.append(ast.parse(arguments[index + 1].value))
                assert len(producers) == 2  # Actual outer process and its Python child.
                printed = {
                    marker for producer in producers for call in ast.walk(producer)
                    if isinstance(call, ast.Call) and isinstance(call.func, ast.Name)
                    and call.func.id == "print"
                    for argument in call.args
                    if isinstance(argument, ast.Constant) and isinstance(argument.value, str)
                    for marker in MARKER.findall(argument.value)
                }
                # A forwarding whitelist accepts output; it does not emit it.
                # preview_effects has no producer in this caller entrypoint.
                emitted.difference_update(forwarded)
                emitted.update(printed)
            if "[DQ:cap_${path//" in check:
                paths, = re.findall(r"for path in ([a-z_/ ]+); do", check)
                emitted.update("cap_" + path.replace("/", "_") for path in paths.split())
            if "[DQ:inspection_recap_'+str(number)+']" in check:
                numbers, = re.findall(r"for number in \(([0-9,]+)\):", check)
                emitted.update("inspection_recap_" + value for value in numbers.split(","))
            for body in re.findall(r"<<'(DQ_NOTICE|DQ_PRIVATE_DECLARED_ONLY)'\n(.*?)\n\1(?:\n|$)", check, re.S):
                for node in ast.walk(ast.parse(body[1])):
                    if not isinstance(node, ast.For) or not isinstance(node.iter, ast.List):
                        continue
                    if not isinstance(node.target, ast.Tuple):
                        continue
                    variables = [name.id for name in node.target.elts if isinstance(name, ast.Name)]
                    if "marker" not in variables:
                        continue
                    position = variables.index("marker")
                    for item in node.iter.elts:
                        value = item.elts[position]
                        if isinstance(value, ast.Constant) and isinstance(value.value, str):
                            emitted.add(value.value)
            emitted.update(
                f"{prefix}{host}"
                for prefix in FLEET_MARKER.findall(check)
                for host in (1, 2, 3)
            )
            if "routes_{host}" in check:
                emitted.update(f"routes_{host}" for host in (1, 2, 3))
            if "directory_{route}_{host}" in check:
                emitted.update(
                    f"directory_{route}_{host}"
                    for route in ("north", "south", "east")
                    for host in (1, 2, 3)
                )
            if "require(found,'state')" in check:
                emitted.add("state")
            if "dialect='by_counter'" in check:
                emitted.update(
                    f"recap_{host}_{counter}"
                    for host in (1, 2, 3)
                    for counter in ("changed", "failed")
                )
            if "DQ_TEMPLATE_CAPABILITY" in check:
                emitted.update(re.findall(r"'(template_(?:render|inputs|observation))'", check))
            if "DQ_CPU_POLICY" in check or "DQ_CPU_STARTUP" in check:
                emitted.update(re.findall(r"'(cpu_[a-z_]+)'", check))
            if "dialect='by_host'" in check:
                emitted.update(f"recap_{host}" for host in (1, 2, 3))
            for body in re.findall(r"<<'DQ_BOSS'\n(.*?)\nDQ_BOSS(?:\n|$)", check, re.S):
                for call in ast.walk(ast.parse(body)):
                    if (isinstance(call, ast.Call)
                            and isinstance(call.func, ast.Name)
                            and call.func.id == "require"
                            and len(call.args) > 1
                            and isinstance(call.args[1], ast.Constant)
                            and isinstance(call.args[1].value, str)):
                        emitted.add(call.args[1].value)
            for body in re.findall(
                r"<<'(?:DQ_MAINTENANCE_(?:POLICY|EVICTIONS)|DQ_RECOVERY_CONSUMERS)'\n(.*?)\n(?:DQ_MAINTENANCE_(?:POLICY|EVICTIONS)|DQ_RECOVERY_CONSUMERS)(?:\n|$)",
                check, re.S,
            ):
                # The producer prints the current failure variable. Its source
                # assignments identify the phase-specific emitted keys; merely
                # declaring a message in the lookup table does not emit it.
                for node in ast.walk(ast.parse(body)):
                    if (isinstance(node, ast.Assign)
                            and any(isinstance(target, ast.Name) and target.id == "failure"
                                    for target in node.targets)
                            and isinstance(node.value, ast.Constant)
                            and isinstance(node.value.value, str)):
                        emitted.add(node.value.value)
            for delimiter, body in re.findall(
                r"<<'(DQ_HEARTBEAT|DQ_INGRESS_ROUTE|DQ_ROLLING|DQ_SECURITY)'\n(.*?)\n\1(?:\n|$)",
                check, re.S,
            ):
                tree = ast.parse(body)
                if delimiter in {"DQ_HEARTBEAT", "DQ_INGRESS_ROUTE"}:
                    for node in tree.body:
                        if not isinstance(node, ast.Assign) or not isinstance(node.value, ast.List):
                            continue
                        if any(isinstance(target, ast.Name) and target.id == "checks"
                               for target in node.targets):
                            emitted.update(ast.literal_eval(item.elts[0]) for item in node.value.elts)
                if delimiter == "DQ_ROLLING":
                    for node in ast.walk(tree):
                        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                                and isinstance(node.func.value, ast.Name)
                                and node.func.value.id == "checks" and node.func.attr == "append"):
                            emitted.add(ast.literal_eval(node.args[0].elts[0]))
                if delimiter == "DQ_SECURITY":
                    for node in tree.body:
                        # Explicitly disabled extensions do not emit live markers.
                        if isinstance(node, ast.If) and isinstance(node.test, ast.Constant) and node.test.value is False:
                            continue
                        for call in ast.walk(node):
                            if (isinstance(call, ast.Call) and isinstance(call.func, ast.Name)
                                    and call.func.id == "emit" and isinstance(call.args[0], ast.Constant)):
                                emitted.add(ast.literal_eval(call.args[0]))
                        if isinstance(node, ast.For) and isinstance(node.target, ast.Name) and node.target.id == "field":
                            emitted.update("host_" + field.lower() for field in ast.literal_eval(node.iter))
            if "[DQ:status_${field,,}]" in check:
                emitted.update(
                    "status_" + field.lower()
                    for field in re.findall(r"^field=(\w+)$", check, re.M)
                )
            if "[DQ:field_${field,,}]" in check:
                emitted.update("field_" + field.lower() for field in re.findall(r"^field=(\w+)$", check, re.M))
            if "[DQ:http_${name//-/_}]" in check:
                emitted.update("http_" + name.replace("-", "_")
                               for name in re.findall(r"^name=([a-z0-9-]+)$", check, re.M))
            for body in re.findall(r"<<'DQ_SERVICE_CONTRACTS'\n(.*?)\nDQ_SERVICE_CONTRACTS(?:\n|$)", check, re.S):
                tree = ast.parse(body)
                for call in ast.walk(tree):
                    if (isinstance(call, ast.Call) and isinstance(call.func, ast.Name)
                            and call.func.id == "report" and isinstance(call.args[0], ast.Constant)):
                        emitted.add(ast.literal_eval(call.args[0]))
                name_loop, = (node for node in tree.body if isinstance(node, ast.For)
                              and isinstance(node.target, ast.Name) and node.target.id == "name")
                field_loop, = (node for node in name_loop.body if isinstance(node, ast.For)
                               and isinstance(node.target, ast.Name) and node.target.id == "field")
                emitted.update(f"contract_{name.replace('-', '_')}_{field.lower()}"
                               for name in ast.literal_eval(name_loop.iter)
                               for field in ast.literal_eval(field_loop.iter))
            if "[DQ:$id]" in check:
                emitted.update(re.findall(r"^check ([a-z0-9_]+) ", check, re.M))
            if "[DQ:uid_$name]" in check:
                names, = re.findall(r"^for name in ([a-z ]+); do$", check, re.M)
                emitted.update("uid_" + name for name in names.split())
            if "[DQ:denied_${path//\\//_}]" in check:
                paths, = re.findall(r"^for path in ([a-z/ ]+); do$", check, re.M)
                emitted.update("denied_" + path.replace("/", "_") for path in paths.split())
            for _, body in re.findall(
                r"<<'(DQ_DISCOVERY_CONSUMER|DQ_LOAD_INPUTS|DQ_LOAD_DEMAND|DQ_ATTACHMENT_CURRENT)'\n(.*?)\n\1(?:\n|$)",
                check, re.S,
            ):
                for call in ast.walk(ast.parse(body)):
                    if not isinstance(call, ast.Call) or not isinstance(call.func, ast.Name):
                        continue
                    index = {"require": 1, "command": 1, "get": 2}.get(call.func.id)
                    if index is not None and len(call.args) > index and isinstance(call.args[index], ast.Constant):
                        emitted.add(ast.literal_eval(call.args[index]))
            for body in re.findall(r"<<'DQ_QUANTITY'\n(.*?)\nDQ_QUANTITY(?:\n|$)", check, re.S):
                for node in ast.walk(ast.parse(body)):
                    if (isinstance(node, ast.For) and isinstance(node.target, ast.Tuple)
                            and any(isinstance(name, ast.Name) and name.id == "marker" for name in node.target.elts)):
                        index = [name.id for name in node.target.elts].index("marker")
                        emitted.update(values[index] for values in ast.literal_eval(node.iter) if values[index])
            if "[DQ:owner_$marker]" in check:
                resources, = re.findall(r"^for resource in ([a-z/ -]+); do$", check, re.M)
                emitted.update("owner_" + name.replace("/", "_").replace("-", "_")
                               for name in resources.split())
            for _, body in re.findall(
                r"<<'(DQ_RECONCILIATION_DELIVERY|DQ_RECONCILIATION_IDENTITY|DQ_VIP_ENDPOINTS)'\n(.*?)\n\1(?:\n|$)",
                check, re.S,
            ):
                for call in ast.walk(ast.parse(body)):
                    if not isinstance(call, ast.Call) or not isinstance(call.func, ast.Name):
                        continue
                    index = {"require": 1, "command": 1, "get": 2}.get(call.func.id)
                    if index is not None and len(call.args) > index and isinstance(call.args[index], ast.Constant):
                        emitted.add(ast.literal_eval(call.args[index]))
            for delimiter, body in re.findall(
                r"<<'(DQ_POLICY|DQ_BOSS)'\n(.*?)\n\1(?:\n|$)", check, re.S,
            ):
                if "expected-actual" not in body and "expected - actual" not in body:
                    continue
                tree = ast.parse(body)
                for call in ast.walk(tree):
                    if (isinstance(call, ast.Call) and isinstance(call.func, ast.Name)
                            and call.func.id == "issue" and isinstance(call.args[0], ast.Constant)):
                        emitted.add(ast.literal_eval(call.args[0]))
                expected, = (node.value for node in ast.walk(tree)
                             if isinstance(node, ast.Assign) and isinstance(node.value, ast.Set)
                             and any(isinstance(target, ast.Name) and target.id == "expected"
                                     for target in node.targets))
                for entry in expected.elts:
                    destination, protocol, port = entry.elts
                    if isinstance(destination, ast.Name):
                        assert delimiter == "DQ_POLICY" and destination.id == "target"
                        name, = re.findall(r'/dev/fd/4 "([a-z]+)" /dev/fd/5', check)
                    else:
                        name = ast.literal_eval(destination)
                    emitted.add(f"missing_{name}_{ast.literal_eval(protocol).lower()}_{ast.literal_eval(port)}")
            for label, body in re.findall(
                r"<<'(DQ_ADOPTION_CURRENT|DQ_AUTHORITY_POLICY|DQ_AUTHORITY_REQUESTS)'\n(.*?)\n\1(?:\n|$)", check, re.S
            ):
                positions = {"require": 1} if label == "DQ_ADOPTION_CURRENT" else {
                    "require": 1, "command": 1, "get": 1
                }
                for call in ast.walk(ast.parse(body)):
                    if isinstance(call, ast.Call) and isinstance(call.func, ast.Name):
                        position = positions.get(call.func.id)
                        if position is not None and len(call.args) > position:
                            value = call.args[position]
                            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                                emitted.add(value.value)
            for variable in ("name", "station"):
                markers_with_suffix = re.findall(r"\[DQ:([a-z0-9_]+_)\$\{" + variable + r"\}\]", check)
                if markers_with_suffix:
                    loop_values, = re.findall(r"^for " + variable + r" in ([a-z ]+); do$", check, re.M)
                    emitted.update(marker + value for marker in markers_with_suffix
                                   for value in loop_values.split())
            if r"[DQ:denied_${path//\//_}]" in check:
                paths, = re.findall(r"^for path in ([a-z/ ]+); do$", check, re.M)
                emitted.update("denied_" + path.replace("/", "_") for path in paths.split())
            for _, body in re.findall(
                r"<<'(DQ_QUOTA|DQ_DEFAULTS|DQ_ADMITTED|DQ_ADMISSION_POLICY|DQ_ADMISSION_CONSUMERS|"
                r"DQ_OBSERVER_INPUTS|DQ_OBSERVER_DELIVERY|DQ_CHECKPOINT_SNAPSHOT|DQ_CHECKPOINT_RESTORE|"
                r"DQ_RETIREMENT)'\n(.*?)\n\1(?:\n|$)", check, re.S
            ):
                for call in ast.walk(ast.parse(body)):
                    if isinstance(call, ast.Call) and isinstance(call.func, ast.Name):
                        position = {"emit": 0, "require": 1}.get(call.func.id)
                        if position is not None and len(call.args) > position:
                            value = call.args[position]
                            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                                emitted.add(value.value)
            if '[DQ:${query}_value]' in check:
                queries = re.findall(r"^query=([a-z]+)$", check, re.M)
                suffixes = re.findall(r'check "\$\{query\}_([a-z]+)"', check)
                emitted.update(f"{query}_{suffix}" for query in queries for suffix in (*suffixes, "value"))
            if quest == 130:
                for body in re.findall(r"<<'DQ_BOSS'\n(.*?)\nDQ_BOSS(?:\n|$)", check, re.S):
                    for node in ast.walk(ast.parse(body)):
                        if (isinstance(node, ast.Assign) and isinstance(node.value, ast.List)
                                and any(isinstance(target, ast.Name) and target.id == "checks"
                                        for target in node.targets)):
                            emitted.update(ast.literal_eval(item.elts[0]) for item in node.value.elts)
            assert emitted, (quest, goal["text"])
            markers.update(emitted)
    explanations = catalog.public(quest)["diagnostics"]
    assert set(explanations) == markers
    for values in explanations.values():
        assert set(values) == set(catalog.resources.languages)
        assert len(set(GUIDE_LINK.findall(values["en"]))) == 1
        for text in values.values():
            link, = GUIDE_LINK.finditer(text)
            assert text[:link.start()].strip()
            assert "\n" not in text.strip()


def test_diagnostic_guide_targets_exist_in_every_reader_language(catalog):
    sections = {}
    for quest in catalog.quests:
        for marker, values in catalog.public(quest)["diagnostics"].items():
            destinations = GUIDE_LINK.findall(values["en"])
            for language, text in values.items():
                assert GUIDE_LINK.findall(text) == destinations, (quest, marker, language)
            for guide, anchor in destinations:
                if guide not in sections:
                    sections[guide] = {
                        language: SECTION.findall(text)
                        for language, text in catalog.guide(guide)["content"].items()
                    }
                for language in catalog.resources.languages:
                    assert sections[guide][language].count(anchor) == 1, (guide, anchor, language)
