"""Re-hash the Russian guide texts after editing them; translations then show as stale.

The Russian text in docs/guides/<resource>/i18n/ru.yaml is the source of truth.
"""

import json

import yaml

from devops_quests.catalog import ROOT
from scripts.validate_i18n import digest


def refresh(root=ROOT):
    index_path = root / "docs/guide-excerpts.json"
    index = json.loads(index_path.read_text())
    refreshed = set()
    for item in index.values():
        resource = item["resource"]
        path = root / "docs/guides" / resource / "i18n/ru.yaml"
        values = yaml.safe_load(path.read_text())
        item["source_hash"] = digest(values["text"])
        if resource not in refreshed:
            values["source_hash"] = item["source_hash"]
            path.write_text(
                yaml.safe_dump(
                    values, allow_unicode=True, sort_keys=False, width=100000
                )
            )
            refreshed.add(resource)
    index_path.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n")
    return len(refreshed)


if __name__ == "__main__":
    print("Re-hashed Russian guides:", refresh())
