"""Validate language coverage, guide provenance and unchanged operational code."""

import argparse
import hashlib
import json
from pathlib import Path

import yaml

from devops_quests.catalog import ROOT
from devops_quests.code_translation import same_code
from devops_quests.i18n import LANGUAGE


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def quest_keys(quest):
    keys = {
        quest["title"],
        quest["brief"],
        quest["debrief"],
        *quest["phrases"],
    }
    for question in quest.get("questions", []):
        keys.update(
            [question]
            if isinstance(question, str)
            else [question["prompt"], *question["points"]]
        )
    for stage in quest["stages"]:
        keys.add(stage["brief"])
        keys.update(goal["text"] for goal in stage["objectives"])
    for hint in quest["hints"]:
        keys.add(hint["text"])
        if "label" in hint:
            keys.add(hint["label"])
    return keys


def audit(root=ROOT):
    root = Path(root)
    errors, missing, stale = [], {}, []
    languages = sorted(
        p.name
        for p in (root / "locales").iterdir()
        if p.is_dir() and LANGUAGE.fullmatch(p.name)
    )
    bundles = [
        (root / "locales", "ui.json", True),
        (root / "locales", "levels.json", True),
    ]
    if (root / "locales/en/interview.json").exists():
        bundles.append((root / "locales", "interview.json", True))
    bundles += [
        (p.parent / "i18n", None, False)
        for p in sorted((root / "quests").glob("*/quest.yaml"))
    ]
    bundles += [
        (p / "i18n", None, False)
        for p in sorted((root / "docs/guides").iterdir())
        if p.is_dir()
    ]
    resources = {}
    for directory, filename, nested in bundles:
        label = str(directory.relative_to(root)) + ("/" + filename if filename else "")
        values = {}
        for language in languages:
            path = (
                directory / language / filename
                if nested
                else directory / (language + ".yaml")
            )
            if not path.exists():
                values[language] = {}
                continue
            try:
                data = (
                    json.loads(path.read_text())
                    if path.suffix == ".json"
                    else yaml.safe_load(path.read_text())
                )
                if not isinstance(data, dict) or any(
                    not isinstance(k, str) or not isinstance(v, str)
                    for k, v in data.items()
                ):
                    raise ValueError(
                        "Resources must be a flat string-to-string mapping"
                    )
                values[language] = data
            except (ValueError, yaml.YAMLError) as error:
                errors.append(
                    {"bundle": label, "language": language, "error": str(error)}
                )
                values[language] = {}
        english = values.get("en", {})
        if not english:
            errors.append({"bundle": label, "error": "missing_english"})
        all_keys = set().union(*(set(x) for x in values.values()))
        for key in sorted(all_keys):
            if not english.get(key):
                errors.append(
                    {"bundle": label, "key": key, "error": "missing_english_key"}
                )
        for language in languages:
            absent = sorted(key for key in english if not values[language].get(key))
            if absent:
                missing.setdefault(language, {})[label] = absent
        resources[str(directory) + ("/" + filename if filename else "")] = values
    for path in sorted((root / "quests").glob("*/quest.yaml")):
        try:
            quest = yaml.safe_load(path.read_text())
            keys = quest_keys(quest)
            english = resources[str(path.parent / "i18n")]["en"]
            for key in keys:
                if not english.get(key):
                    errors.append(
                        {
                            "quest": quest["id"],
                            "key": key,
                            "error": "missing_english_reference",
                        }
                    )
        except (KeyError, TypeError) as error:
            errors.append(
                {
                    "quest": str(path.relative_to(root)),
                    "error": "invalid_language_independent_structure",
                    "detail": str(error),
                }
            )
    levels_path = root / "levels.yaml"
    if levels_path.exists():
        english_levels = resources[str(root / "locales") + "/levels.json"].get("en", {})
        for level in yaml.safe_load(levels_path.read_text()):
            for field in ("skill", "story"):
                if not english_levels.get(level[field]):
                    errors.append(
                        {
                            "level": level["id"],
                            "key": level[field],
                            "error": "missing_english_reference",
                        }
                    )
    theory = root / "docs/interview-topics.yaml"
    if theory.exists():
        english = resources.get(str(root / "locales") + "/interview.json", {}).get(
            "en", {}
        )
        for topic in yaml.safe_load(theory.read_text()):
            keys = {topic["title"]}
            for question in topic["questions"]:
                keys.update([question["prompt"], *question["points"]])
            for key in keys:
                if not english.get(key):
                    errors.append(
                        {
                            "topic": topic["id"],
                            "key": key,
                            "error": "missing_english_reference",
                        }
                    )
    index = json.loads((root / "docs/guide-excerpts.json").read_text())
    for name, item in index.items():
        values = resources[str(root / "docs/guides" / item["resource"] / "i18n")]
        original = values.get("ru", {}).get("text", "")
        if digest(original) != item["source_hash"]:
            errors.append({"guide": name, "error": "original_hash_mismatch"})
        for language, translation in values.items():
            if not translation:
                continue
            if translation.get("source_hash") != item["source_hash"]:
                stale.append(
                    {"guide": name, "language": language, "reason": "snapshot_changed"}
                )
            try:
                if not same_code(original, translation.get("text", "")):
                    errors.append(
                        {
                            "guide": name,
                            "language": language,
                            "error": "code_blocks_changed",
                        }
                    )
            except ValueError as error:
                errors.append({"guide": name, "error": str(error)})
    return {
        "languages": languages,
        "bundles": len(bundles),
        "guide_links": len(index),
        "missing": missing,
        "errors": errors,
        "stale": stale,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail on missing optional translations too",
    )
    args = parser.parse_args()
    result = audit(args.root)
    if args.output:
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(
        f"Bundles: {result['bundles']}; guide links: {result['guide_links']}; errors: {len(result['errors'])}; stale: {len(result['stale'])}"
    )
    for language in result["languages"]:
        print(
            language
            + ": "
            + str(sum(len(x) for x in result["missing"].get(language, {}).values()))
            + " missing keys"
        )
    raise SystemExit(
        bool(result["errors"] or result["stale"] or (args.strict and result["missing"]))
    )


if __name__ == "__main__":
    main()
