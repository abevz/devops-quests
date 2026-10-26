import json
import re
from collections import Counter

import yaml

from devops_quests.catalog import Catalog, ROOT
from devops_quests.code_translation import fenced_blocks


def test_spanish_machine_translation_covers_all_public_content_and_keeps_code():
    catalog = Catalog()
    metadata = catalog.resources.metadata["es"]
    assert metadata["translation"] == "machine"
    assert metadata["translation_label"] == "traducción automática"
    assert metadata["source_language"] == "en"
    assert metadata["meaning_reference"] == "ru"
    for number, quest in catalog.quests.items():
        assert catalog.text(number, quest["title"])["es"]
    for level in catalog.public_levels():
        assert level["skill"]["es"] and level["story"]["es"]
    for name in catalog.guide_lessons:
        guide = catalog.guide(name)
        assert all(guide[field]["es"] for field in ("titles", "content", "reference"))
        assert not guide["lesson_stale"]
        if guide["additional"]:
            assert guide["additional"]["es"]
        assert fenced_blocks(guide["content"]["es"]) == fenced_blocks(
            guide["content"]["en"]
        )
    for number, key, literal in [
        (64, "hints.0.text", "each.key"),
        (107, "brief", "station.internal"),
        (113, "brief", "north.station.internal"),
        (129, "brief", "training.devops-quests.local/cleanup"),
        (99, "brief", "rail-rotation"),
        (99, "brief", "rail-reader"),
        (94, "brief", "50m"),
    ]:
        assert literal in catalog.text(number, key)["es"]
    # Exact inline-code spans and fenced blocks retain commands and their literals.
    sources = [
        *ROOT.glob("quests/*/i18n/en.yaml"),
        *ROOT.glob("docs/guides/*/i18n/en.yaml"),
        *ROOT.glob("locales/en/*.json"),
    ]
    for path in sources:
        target = (
            path.with_name("es.yaml")
            if path.suffix == ".yaml"
            else path.parent.parent / "es" / path.name
        )
        read = json.loads if path.suffix == ".json" else yaml.safe_load
        source, translation = read(path.read_text()), read(target.read_text())
        assert source.keys() == translation.keys(), str(path)
        for key, text in source.items():
            assert Counter(re.findall(r"`[^`\n]+`", text)) == Counter(
                re.findall(r"`[^`\n]+`", translation[key])
            ), (path, key)
            assert fenced_blocks(text) == fenced_blocks(translation[key]), (path, key)
