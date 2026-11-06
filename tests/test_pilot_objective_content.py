"""Keep live objectives useful without duplicate summaries or log answers."""

import re
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
SUMMARY = re.compile(
    r"^(?:Initial success criteria|Success criteria|"
    r"Цели первого этапа|Результат проверки|"
    r"Erste Erfolgskriterien|Erfolgskriterium|Erfolgskriterien|"
    r"Criterios de éxito iniciales|Criterios de éxito|"
    r"Wstępne kryteria sukcesu|Początkowe kryteria sukcesu|Kryteria sukcesu):"
)


@pytest.mark.parametrize("path", sorted((ROOT / "quests").glob("*/quest.yaml")),
                         ids=lambda path: path.parent.name)
def test_multi_objective_briefs_have_no_success_summary(path):
    quest = yaml.safe_load(path.read_text())
    # Include 001: its revised single objective also replaces the old summary.
    if quest["id"] != 1 and not any(
        len(stage["objectives"]) > 1 for stage in quest["stages"]
    ):
        return
    for resource in sorted((path.parent / "i18n").glob("*.yaml")):
        texts = yaml.safe_load(resource.read_text())
        for key, text in texts.items():
            if key == "brief" or re.fullmatch(r"stages\.\d+\.brief", key):
                for paragraph in text.split("\n\n"):
                    assert not SUMMARY.match(paragraph.lstrip()), (resource, key)


@pytest.mark.parametrize("language", ["en", "ru", "de", "es", "pl"])
def test_014_objectives_do_not_reveal_log_answers(language):
    texts = yaml.safe_load(
        (ROOT / f"quests/014/i18n/{language}.yaml").read_text()
    )
    objectives = "\n".join(
        text for key, text in texts.items() if ".objectives." in key
    )
    assert "route must equal north" not in objectives
    assert "ROUTE=north" not in objectives
    assert "diagnosis.txt" in texts["stages.0.objectives.0.text"]


@pytest.mark.parametrize("language", ["en", "ru", "de", "es", "pl"])
def test_045_objective_names_required_volume_contract(language):
    texts = yaml.safe_load(
        (ROOT / f"quests/045/i18n/{language}.yaml").read_text()
    )
    # Required result identifiers must stay explicit even if absent from brief.
    objective = texts["stages.0.objectives.1.text"]
    for identifier in ["reader", "route-data", "data", "/data"]:
        assert f"`{identifier}`" in objective, (language, identifier)


@pytest.mark.parametrize("language", ["en", "ru", "de", "es", "pl"])
@pytest.mark.parametrize("quest,objective,requirement", [
    (14, 2, "`ROUTE`"),
    (17, 2, "`Ready=False`"),
    (45, 0, "Bound"),
])
def test_pilot_objectives_name_exact_result_requirements(
    language, quest, objective, requirement
):
    texts = yaml.safe_load(
        (ROOT / f"quests/{quest:03}/i18n/{language}.yaml").read_text()
    )
    assert requirement in texts[f"stages.0.objectives.{objective}.text"]
