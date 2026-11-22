"""Condition explanations link to named sections in the public guide."""

import ast
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


@pytest.mark.parametrize("quest", range(1, 41))
def test_each_migrated_condition_has_a_localized_explanation_and_guide(catalog, quest):
    markers = set()
    for stage in catalog.quests[quest]["stages"]:
        for goal in stage["objectives"]:
            check = goal["check"]
            emitted = set(MARKER.findall(check))
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
