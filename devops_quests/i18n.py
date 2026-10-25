"""File-backed language resources; English is the required fallback."""

import json
import re
from pathlib import Path

import yaml

LANGUAGE = re.compile(r"[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\Z")


def read_resources(directory, suffix=".yaml"):
    result = {}
    for path in sorted(Path(directory).glob("*" + suffix)):
        if LANGUAGE.fullmatch(path.stem):
            result[path.stem] = (
                json.loads(path.read_text())
                if suffix == ".json"
                else yaml.safe_load(path.read_text())
            )
    if "en" not in result:
        raise ValueError(f"Missing English resource: {directory}")
    return result


class Resources:
    def __init__(self, root):
        self.root = Path(root)
        self.ui = {
            p.parent.name: json.loads(p.read_text())
            for p in sorted((self.root / "locales").glob("*/ui.json"))
            if LANGUAGE.fullmatch(p.parent.name)
        }
        if "en" not in self.ui:
            raise ValueError("Missing English UI resource")
        self.languages = tuple(self.ui)
        self.metadata = {
            lang: json.loads(path.read_text())
            for lang in self.languages
            if (path := self.root / "locales" / lang / "metadata.json").exists()
        }

    @staticmethod
    def values(resources, key):
        if key not in resources["en"]:
            raise ValueError(f"Missing English message: {key}")
        return {
            lang: values[key] for lang, values in resources.items() if key in values
        }

    def preferences(self, primary=None, translation=None):
        if primary is not None and primary not in self.languages:
            raise ValueError("preferences.unsupported_language")
        if translation not in (None, "none") and translation not in self.languages:
            raise ValueError("preferences.unsupported_language")
        return {"primary": primary, "translation": translation}
