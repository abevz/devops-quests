"""Validate language coverage, guide provenance and unchanged operational code."""

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

import yaml

from devops_quests.catalog import ROOT
from devops_quests.code_translation import fenced_blocks, same_code
from devops_quests.i18n import LANGUAGE

DOTTED_LITERAL = re.compile(
    r"(?<![\w.-])[A-Za-z_][\w-]*(?:\.[A-Za-z_][\w-]*)+(?:/[\w./-]+)?"
)
RESOURCE_QUANTITY = re.compile(r"\b\d+(?:\.\d+)?(?:m|Mi|Gi|Ki|Ti|ms)\b")
HYPHENATED_LITERAL = re.compile(r"\b[A-Za-z][A-Za-z0-9_]*(?:-[A-Za-z0-9_]+)+\b")
# Synthetic workload identities also occur as plain prose, outside code spans.
WORKLOAD_NAMES = re.compile(
    r"\b(?:board|relay|worker|station|client|reader|dispatcher|visitor|shelf)\b",
    re.IGNORECASE,
)


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
    machine_languages = set()
    for language in languages:
        path = root / "locales" / language / "metadata.json"
        if not path.exists():
            continue
        try:
            metadata = json.loads(path.read_text())
            if not isinstance(metadata, dict):
                raise ValueError("Language metadata must be an object")
            if metadata.get("translation") == "machine":
                machine_languages.add(language)
                if (
                    not isinstance(metadata.get("translation_label"), str)
                    or not metadata["translation_label"].strip()
                ):
                    raise ValueError(
                        "Machine translation requires a native-language label"
                    )
                if metadata.get("source_language") != "en":
                    raise ValueError(
                        "Machine translations must identify the English source"
                    )
        except (ValueError, TypeError) as error:
            errors.append(
                {
                    "language": language,
                    "error": "invalid_metadata",
                    "detail": str(error),
                }
            )

    quest_literals = {}
    for path in (root / "quests").glob("*/quest.yaml"):
        assets = [path, *path.parent.glob("*.sh")]
        text = "\n".join(asset.read_text() for asset in assets)
        quest_literals[str(path.parent.relative_to(root) / "i18n")] = set(
            HYPHENATED_LITERAL.findall(text)
        )

    def exact_machine_code(label, values):
        for language in machine_languages:
            for key, source in values.get("en", {}).items():
                target = values.get(language, {}).get(key)
                if target is None:
                    continue
                try:
                    if fenced_blocks(source) != fenced_blocks(target):
                        errors.append(
                            {
                                "bundle": label,
                                "language": language,
                                "key": key,
                                "error": "code_blocks_changed",
                            }
                        )
                    source_literals = Counter(
                        x.rstrip(".") for x in DOTTED_LITERAL.findall(source)
                    )
                    target_literals = Counter(
                        x.rstrip(".") for x in DOTTED_LITERAL.findall(target)
                    )
                    identifiers = quest_literals.get(label, set())
                    # A shared literal in the Russian reference distinguishes an
                    # identifier from coincidental hyphenated English prose.
                    reference = {
                        x.lower()
                        for x in HYPHENATED_LITERAL.findall(
                            values.get("ru", {}).get(key, "")
                        )
                    }
                    identifiers = {x for x in identifiers if x.lower() in reference}
                    source_literals.update(
                        x
                        for x in HYPHENATED_LITERAL.findall(source)
                        if x in identifiers
                    )
                    target_literals.update(
                        x
                        for x in HYPHENATED_LITERAL.findall(target)
                        if x in identifiers
                    )
                    if changed := source_literals - target_literals:
                        errors.append(
                            {
                                "bundle": label,
                                "language": language,
                                "key": key,
                                "error": "technical_literals_changed",
                                "missing": sorted(changed.elements()),
                            }
                        )
                    source_quantities = Counter(RESOURCE_QUANTITY.findall(source))
                    target_quantities = Counter(RESOURCE_QUANTITY.findall(target))
                    if changed := source_quantities - target_quantities:
                        errors.append(
                            {
                                "bundle": label,
                                "language": language,
                                "key": key,
                                "error": "resource_quantities_changed",
                                "missing": sorted(changed.elements()),
                            }
                        )
                    if label.startswith("quests/"):
                        source_names = Counter(
                            x.lower() for x in WORKLOAD_NAMES.findall(source)
                        )
                        target_names = Counter(
                            x.lower() for x in WORKLOAD_NAMES.findall(target)
                        )
                        if changed := source_names - target_names:
                            errors.append(
                                {
                                    "bundle": label,
                                    "language": language,
                                    "key": key,
                                    "error": "workload_names_changed",
                                    "missing": sorted(changed.elements()),
                                }
                            )
                except ValueError as error:
                    errors.append(
                        {
                            "bundle": label,
                            "language": language,
                            "key": key,
                            "error": str(error),
                        }
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
        exact_machine_code(label, values)

    # These published UI titles and practical lessons live outside flat bundles.
    for filename, field in [
        ("guide-lessons.yaml", "content"),
        ("guide-lessons.yaml", "additional"),
        ("guide-topics.yaml", None),
    ]:
        path = root / "docs" / filename
        if not path.exists():
            continue
        for name, item in yaml.safe_load(path.read_text()).items():
            if field == "additional" and not item.get(field):
                continue
            label = f"docs/{filename}/{name}"
            if field == "additional":
                label += "/additional"
            values = item[field] if field else item
            if not values.get("en"):
                errors.append({"bundle": label, "error": "missing_english"})
            for language in languages:
                if not values.get(language):
                    missing.setdefault(language, {})[label] = [field or "title"]
            exact_machine_code(
                label, {lang: {"text": text} for lang, text in values.items()}
            )
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
