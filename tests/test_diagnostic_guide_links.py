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


@pytest.mark.parametrize("quest", range(1, 74))
def test_each_migrated_condition_has_a_localized_explanation_and_guide(catalog, quest):
    markers = set()
    for stage in catalog.quests[quest]["stages"]:
        for goal in stage["objectives"]:
            check = goal["check"]
            emitted = set(MARKER.findall(check))
            for _, body in re.findall(r"<<'(DQ_PROPERTY|DQ_RELEASE_BUNDLE)'\n(.*?)\n\1(?:\n|$)", check, re.S):
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
