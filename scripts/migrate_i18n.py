"""One-time, lossless migration of the original paired quest/level resources."""

import json

import yaml

from devops_quests.catalog import ROOT


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n"
        if path.suffix == ".json"
        else yaml.safe_dump(value, allow_unicode=True, sort_keys=False)
    )


def migrate(root=ROOT):
    for path in sorted((root / "quests").glob("*/quest.yaml")):
        quest = yaml.safe_load(path.read_text())
        if isinstance(quest["title"], str):
            continue
        messages = {}

        def extract(value, key, messages=messages):
            if isinstance(value, dict) and "en" in value:
                for language, text in value.items():
                    messages.setdefault(language, {})[key] = text
                return key
            if isinstance(value, dict):
                return {
                    k: extract(v, f"{key}.{k}".strip(".")) for k, v in value.items()
                }
            if isinstance(value, list):
                return [extract(v, f"{key}.{i}") for i, v in enumerate(value)]
            return value

        quest = extract(quest, "")
        for hint in quest["hints"]:
            hint["guide"] = hint.pop("url").removeprefix("guide/")
            hint.pop("label")
        quest.setdefault("questions", [])
        write(path, quest)
        for language, values in messages.items():
            write(path.parent / "i18n" / (language + ".yaml"), values)
        (path.parent / "brief.md").write_text(
            f"# Quest {quest['id']:03}\n\n"
            + "\n".join(f"- [{lang}](i18n/{lang}.yaml)" for lang in messages)
            + "\n"
        )
    levels = yaml.safe_load((root / "levels.yaml").read_text())
    if "ru" in levels[0]:
        messages = {"en": {}, "ru": {}}
        for level in levels:
            for field in ("skill", "story"):
                key = f"level.{level['id']:03}.{field}"
                messages["en"][key] = level[field]
                messages["ru"][key] = level["ru"][field]
                level[field] = key
            del level["ru"]
        write(root / "levels.yaml", levels)
        for language, values in messages.items():
            write(root / "locales" / language / "levels.json", values)


if __name__ == "__main__":
    migrate()
