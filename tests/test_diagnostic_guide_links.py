"""Condition explanations link to named sections in the public guide."""

import re

import pytest

from devops_quests.catalog import Catalog

GUIDE_LINK = re.compile(
    r"\[[^\]\n]+\]\(guides#guide=([a-z0-9.-]+)&section=([a-z][a-z0-9-]*)\)"
)
SECTION = re.compile(r"^#{2,6}[ \t]+.+[ \t]+\{#([a-z][a-z0-9-]*)\}[ \t]*$", re.M)
MARKER = re.compile(r"\[DQ:([a-z0-9_]+)\]")


@pytest.fixture(scope="module")
def catalog():
    return Catalog()


@pytest.mark.parametrize("quest", (1, 3, 4, 7, 9))
def test_each_pilot_condition_has_a_localized_explanation_and_guide(catalog, quest):
    markers = {
        marker
        for stage in catalog.quests[quest]["stages"]
        for goal in stage["objectives"]
        for marker in MARKER.findall(goal["check"])
    }
    assert len(markers) == sum(
        len(stage["objectives"]) for stage in catalog.quests[quest]["stages"]
    )
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
