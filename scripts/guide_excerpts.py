"""Refresh Russian guide snapshots; keep translations and mark old hashes stale."""

import argparse
import json
from pathlib import Path

import yaml

from devops_quests.catalog import ROOT
from scripts.validate_i18n import digest, extract_source


def refresh(vault, root=ROOT):
    index_path = root / "docs/guide-excerpts.json"
    index = json.loads(index_path.read_text())
    refreshed = set()
    for item in index.values():
        text, line = extract_source(vault, item)
        item["line"] = line
        item["source_hash"] = digest(text)
        resource = item["resource"]
        if resource not in refreshed:
            path = root / "docs/guides" / resource / "i18n/ru.yaml"
            path.write_text(
                yaml.safe_dump(
                    {
                        "heading": item["heading"],
                        "text": text,
                        "source_hash": item["source_hash"],
                    },
                    allow_unicode=True,
                    sort_keys=False,
                    width=100000,
                )
            )
            refreshed.add(resource)
    index_path.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n")
    return len(refreshed)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", type=Path, required=True)
    args = parser.parse_args()
    print("Refreshed Russian snapshots:", refresh(args.vault))
