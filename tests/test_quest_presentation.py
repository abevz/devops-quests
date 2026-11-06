"""Mechanical rules from docs/quest-authoring.md, "Quest presentation".

A quest is *migrated* once its English brief has a **Requirements:** block. Migrated
quests must follow the presentation rules below in every language. Quests that are not
migrated yet must keep a success-criteria line, so the brief never loses its goal.
"""

import re
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("en", "ru", "de", "es", "pl")
REQUIREMENTS = "**Requirements:**"
VERIFY = "**Verify yourself before Check & finish:**"
BOILERPLATE = "no Internet or external DNS"
CRITERIA = re.compile(r"(?mi)^\s*(?:Initial success criteria|Success criteria)\s*:")
# Quests whose objectives were split before their brief was rewritten (dq-21 #64).
# Their brief is being restored in the K2 briefs batch; remove ids as they migrate.
GOAL_RESTORE_PENDING = {51, 57, 62, 67, 77, 82, 85, 88, 94}
# Machine notation that belongs to checks, not to learner-facing objectives.
MACHINE = re.compile(
    r"\[\s*\{|\{\s*\"|\.spec\.|\.status\.|\.metadata\.|containers\[\d+\]|env\[\d+\]|\bjq\b"
)


def load(number, language="en"):
    path = ROOT / "quests" / f"{number:03}" / "i18n" / f"{language}.yaml"
    return yaml.safe_load(path.read_text())


QUESTS = sorted(int(path.name) for path in (ROOT / "quests").iterdir() if path.name.isdigit())
MIGRATED = [number for number in QUESTS if REQUIREMENTS in load(number)["brief"]]


def stage_briefs(values):
    return {key: value for key, value in values.items() if re.fullmatch(r"stages\.\d+\.brief", key)}


def objectives(values):
    return [value for key, value in values.items() if re.fullmatch(r"stages\.\d+\.objectives\.\d+\.text", key)]


def hints(values):
    return " ".join(value for key, value in values.items() if re.fullmatch(r"hints\.\d+\.text", key))


def verify_commands(brief):
    section = brief.split(VERIFY, 1)[1]
    return [match.strip() for match in re.findall(r"`([^`\n]+)`", section) if " " in match.strip()]


@pytest.mark.parametrize("number", MIGRATED, ids=[f"{n:03}" for n in MIGRATED])
@pytest.mark.parametrize("language", LANGUAGES)
def test_migrated_brief_structure(number, language):
    values = load(number, language)
    brief = values["brief"]
    if language == "en":
        assert REQUIREMENTS in brief and VERIFY in brief
        assert brief.index(REQUIREMENTS) < brief.index(VERIFY)
    # Translations keep the list structure even when headings are localized.
    assert brief.count("\n- ") >= 2, "Requirements and checks must be bulleted lists"
    assert BOILERPLATE not in brief, "Bay facts already state the offline rules"
    assert not CRITERIA.search(brief), "Requirements and objectives replace success criteria"
    for key, text in stage_briefs(values).items():
        assert text.strip(), f"{key} must state the stage goal or constraint"
        assert not CRITERIA.search(text), key


@pytest.mark.parametrize("number", MIGRATED, ids=[f"{n:03}" for n in MIGRATED])
def test_objective_values_are_stated_in_the_brief(number):
    values = load(number)
    brief = values["brief"]
    for text in objectives(values):
        for literal in re.findall(r"`([^`]+)`", text):
            # Whole-token match: "northbound" does not state the value `north`.
            stated = re.search(r"(?<![\w-])" + re.escape(literal) + r"(?![\w-])", brief)
            assert stated, f"objective names `{literal}` but the brief does not"


@pytest.mark.parametrize("number", QUESTS, ids=[f"{n:03}" for n in QUESTS])
def test_objectives_are_human_readable(number):
    for text in objectives(load(number)):
        assert not MACHINE.search(text), f"objective uses check notation: {text}"


@pytest.mark.parametrize("number", MIGRATED, ids=[f"{n:03}" for n in MIGRATED])
def test_self_verification_does_not_repeat_hints(number):
    values = load(number)
    text = hints(values)
    for command in verify_commands(values["brief"]):
        assert command not in text, f"Verify yourself repeats a hint: {command}"


@pytest.mark.parametrize("number", QUESTS, ids=[f"{n:03}" for n in QUESTS])
def test_split_objectives_come_with_a_migrated_brief(number):
    # Splitting objectives removes the old success-criteria line; without a migrated
    # brief the learner loses the goal (owner playtest of 007, 2026-11-06).
    if number in MIGRATED or number in GOAL_RESTORE_PENDING:
        return
    quest = yaml.safe_load((ROOT / "quests" / f"{number:03}" / "quest.yaml").read_text())
    counts = [len(stage["objectives"]) for stage in quest["stages"]]
    assert max(counts) == 1, "migrate the brief in the same change that splits objectives"
