import json
import re
import shutil
from pathlib import Path

import yaml

from devops_quests.catalog import Catalog, public_reference
from scripts import guide_excerpts

ROOT = Path(__file__).resolve().parents[1]


def fences(text):
    result, language, lines = [], None, []
    for line in text.splitlines():
        line = re.sub(r"^(?:> ?)*", "", line)
        if line.startswith("```"):
            if language is None:
                language, lines = line[3:].strip(), []
            else:
                result.append((language, "\n".join(lines)))
                language = None
        elif language is not None:
            lines.append(line)
    assert language is None
    return result


def test_all_published_lessons_have_bilingual_runnable_routes_and_block_coverage():
    catalog = Catalog()
    coverage = yaml.safe_load((ROOT / "labs/coverage.yaml").read_text())
    assert len(coverage) == len(catalog.guide_lessons) == 29
    assert set(coverage) == set(catalog.guide_lessons) == set(catalog.guide_titles)
    count = 0
    for name, lesson in catalog.guide_lessons.items():
        guide = catalog.guide(name)
        row = coverage[name]
        assert not guide["lesson_stale"] and row["source_hash"] == guide["source_hash"]
        assert set(lesson["content"]) == set(catalog.resources.languages)
        for language in catalog.resources.languages:
            assert fences(lesson["content"]["en"]) == fences(
                lesson["content"][language]
            )
        for path in (row["short"], row["full"]):
            assert path.startswith("labs/examples/" + lesson["profile"] + "/")
            for script in ("run.sh", "check.sh", "cleanup.sh"):
                assert (
                    (ROOT / path / script)
                    .read_text()
                    .startswith("#!/bin/bash\nset -euo pipefail")
                )
        blocks = fences(catalog.guide_messages[name]["ru"]["text"])
        assert [(b["block"], b["language"]) for b in row["reference_blocks"]] == [
            (i, language) for i, (language, _) in enumerate(blocks, 1)
        ]
        for block in row["reference_blocks"]:
            if block["category"] == "additional-practicum":
                assert guide["additional"] and "files" not in block
            elif "files" in block:
                assert (ROOT / block["files"]).is_dir()
        count += len(blocks)
    assert count == 378


def test_rehash_after_editing_russian_text_marks_lesson_and_translation_stale(
    tmp_path,
):
    from scripts.validate_i18n import audit

    catalog = Catalog()
    docs = tmp_path / "docs"
    docs.mkdir()
    for name in ("guide-excerpts.json", "guide-lessons.yaml", "guide-topics.yaml"):
        shutil.copyfile(ROOT / "docs" / name, docs / name)
    shutil.copytree(ROOT / "docs/guides", docs / "guides")
    shutil.copytree(ROOT / "locales", tmp_path / "locales")
    before = {
        name: (docs / name).read_bytes()
        for name in ("guide-lessons.yaml", "guide-topics.yaml")
    }
    assert guide_excerpts.refresh(root=tmp_path) == 39
    assert (docs / "guides/kubernetes-20/i18n/ru.yaml").read_bytes() == (
        ROOT / "docs/guides/kubernetes-20/i18n/ru.yaml"
    ).read_bytes()
    russian = docs / "guides/kubernetes-20/i18n/ru.yaml"
    values = yaml.safe_load(russian.read_text())
    values["text"] += "\nEdited text.\n"
    russian.write_text(yaml.safe_dump(values, allow_unicode=True, sort_keys=False))
    assert guide_excerpts.refresh(root=tmp_path) == 39
    for name, expected in before.items():
        assert (docs / name).read_bytes() == expected
    catalog.guides = json.loads((docs / "guide-excerpts.json").read_text())
    assert catalog.guide("kubernetes-20")["lesson_stale"]
    assert (
        catalog.guide("kubernetes-20")["content"]
        == catalog.guide_lessons["kubernetes-20"]["content"]
    )
    result = audit(tmp_path)
    assert not any(e.get("error") == "original_hash_mismatch" for e in result["errors"])
    assert {
        "guide": "kubernetes-20",
        "language": "en",
        "reason": "snapshot_changed",
    } in result["stale"]


def test_public_reference_preserves_numbered_code_lines():
    assert (
        public_reference(
            "### 20.1 A question\n```sh\n## 42 stays code\n```\n### 21 Another"
        )
        == "### A question\n```sh\n## 42 stays code\n```\n### Another"
    )
