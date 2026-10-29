"""Data-only public quest descriptions; executable assets stay server-side."""

import json
import re
from pathlib import Path

import yaml

from .i18n import Resources, read_resources

import os
import sys

_SOURCE_ROOT = Path(__file__).resolve().parents[1]
ROOT = (
    Path(os.environ["DQ_ROOT"]).resolve()
    if os.environ.get("DQ_ROOT")
    else (
        _SOURCE_ROOT
        if (_SOURCE_ROOT / "levels.yaml").is_file()
        else Path(sys.prefix) / "share" / "devops-quests"
    )
)
BANDS = ("basics", "medium", "complex", "expert")
TRACKS = ("Kubernetes", "Ansible", "OpenTofu", "Platform", "Boss")


def public_reference(text):
    """Source numbering is provenance, not the app's reading order."""
    result, fenced = [], False
    for line in text.splitlines():
        if line.lstrip("> ").startswith("```"):
            fenced = not fenced
        if not fenced:
            line = re.sub(r"^(#{2,6}\s+)\d+(?:\.\d+)*\.?\s+", r"\1", line)
        result.append(line)
    return "\n".join(result)


def released_levels(root):
    levels = yaml.safe_load((root / "levels.yaml").read_text())
    return tuple(
        entry["id"]
        for entry in sorted(
            levels, key=lambda item: (BANDS.index(item["difficulty"]), item["id"])
        )
        if (root / "quests" / f"{entry['id']:03}" / "quest.yaml").is_file()
    )


RELEASED = released_levels(ROOT)


class Catalog:
    def __init__(self, root=ROOT):
        self.root = Path(root)
        self.resources = Resources(self.root)
        self.level_messages = {
            lang: json.loads((self.root / "locales" / lang / "levels.json").read_text())
            for lang in self.resources.languages
            if (self.root / "locales" / lang / "levels.json").exists()
        }
        self.levels = yaml.safe_load((self.root / "levels.yaml").read_text())
        self.by_id = {entry["id"]: entry for entry in self.levels}
        self.guides = json.loads((self.root / "docs/guide-excerpts.json").read_text())
        lessons = self.root / "docs/guide-lessons.yaml"
        self.guide_lessons = (
            yaml.safe_load(lessons.read_text()) if lessons.exists() else {}
        )
        self.guide_messages = {
            key: read_resources(self.root / "docs/guides" / key / "i18n")
            for key in {
                item.get("resource", name) for name, item in self.guides.items()
            }
        }
        topics = self.root / "docs/guide-topics.yaml"
        self.guide_titles = (
            yaml.safe_load(topics.read_text()) if topics.exists() else {}
        )
        self.released = released_levels(self.root)
        bank = self.root / "docs/interview-topics.yaml"
        self.interview_topics = (
            yaml.safe_load(bank.read_text()) if bank.exists() else []
        )
        self.interview_messages = {
            lang: json.loads(path.read_text())
            for lang in self.resources.languages
            if (path := self.root / "locales" / lang / "interview.json").exists()
        }
        self.quests = {}
        self.messages = {}
        for number in self.released:
            path = self.root / "quests" / f"{number:03}"
            if (path / "quest.yaml").is_file():
                self.quests[number] = yaml.safe_load((path / "quest.yaml").read_text())
                self.messages[number] = read_resources(path / "i18n")

    def text(self, number, key):
        return Resources.values(self.messages[number], key)

    def public_levels(self):
        return [
            dict(
                level,
                skill=Resources.values(self.level_messages, level["skill"]),
                story=Resources.values(self.level_messages, level["story"]),
            )
            for level in self.levels
        ]

    def guide(self, name):
        item = self.guides[name]
        resource = item.get("resource", name)
        messages = self.guide_messages[resource]
        lesson = self.guide_lessons.get(resource)
        reference = {
            lang: public_reference(value["text"]) for lang, value in messages.items()
        }
        return {
            "id": resource,
            "titles": self.guide_titles.get(
                resource, {lang: value["heading"] for lang, value in messages.items()}
            ),
            "content": lesson["content"] if lesson else reference,
            "reference": reference if lesson else {},
            "profile": lesson["profile"] if lesson else None,
            "example": lesson["example"] if lesson else None,
            "additional": lesson.get("additional", {}) if lesson else {},
            "full_example": lesson.get("full_example", lesson["example"])
            if lesson
            else None,
            "lesson_stale": bool(
                lesson and lesson["source_hash"] != item["source_hash"]
            ),
            "source_language": "ru",
            "source_hash": item["source_hash"],
            "translation_hashes": {
                lang: value.get("source_hash") for lang, value in messages.items()
            },
            "used_in": self.guide_levels(name),
        }

    def guide_levels(self, name):
        resource = self.guides[name].get("resource", name)
        aliases = {
            key
            for key, item in self.guides.items()
            if item.get("resource", key) == resource
        }
        return [
            {"id": number, "title": self.text(number, quest["title"])}
            for number, quest in sorted(self.quests.items())
            if any(hint.get("guide") in aliases for hint in quest["hints"])
        ]

    def guide_index(self):
        groups = {}
        seen = set()
        for name, item in sorted(
            self.guides.items(),
            key=lambda pair: (pair[1]["source"], pair[1]["line"], pair[0]),
        ):
            resource = item.get("resource", name)
            if resource in seen:
                continue
            seen.add(resource)
            topic = Path(item["source"]).stem.removesuffix("-Visual-Guide")
            group = groups.setdefault(topic, {"id": topic, "items": []})
            group["items"].append(
                {
                    "id": resource,
                    "titles": self.guide(name)["titles"],
                    "used_in": self.guide_levels(name),
                    "profile": self.guide_lessons.get(resource, {}).get("profile"),
                }
            )
        return list(groups.values())

    def opened(self, completed, track=None):
        if track is not None and track not in TRACKS:
            raise ValueError("error.track")
        sequence = [
            number
            for number in self.released
            if track is None
            or self.by_id[number]["track"] == track
            or (track == "Boss" and self.by_id[number].get("boss"))
        ]
        done = set(completed)
        result = set(sequence).intersection(done)
        for number in sequence:
            if number not in self.quests:
                break
            result.add(number)
            if number not in done:
                break
        return result

    def briefing(self, number):
        """Public content only: opening this description never prepares a bay."""
        if number not in self.quests:
            raise ValueError("error.level")
        return dict(
            self.public(number),
            dependencies=self.by_id[number]["dependencies"],
            estimated_minutes={
                "basics": [10, 20],
                "medium": [20, 35],
                "complex": [30, 50],
                "expert": [45, 75],
            }[self.by_id[number]["difficulty"]],
        )

    def public(self, number, hints=0, debrief=False, exam=False):
        quest = self.quests[number]
        result = {
            key: quest[key]
            for key in ("id", "title", "brief", "stages", "track", "difficulty")
        }
        for key in ("title", "brief"):
            result[key] = self.text(number, quest[key])
        result["stages"] = [
            {
                "brief": self.text(number, stage["brief"]),
                "objectives": [
                    self.text(number, goal["text"]) for goal in stage["objectives"]
                ],
            }
            for stage in quest["stages"]
        ]

        def guide_link(hint):
            if "url" in hint:
                return {"url": hint["url"], "label": self.text(number, hint["label"])}
            return {
                "url": "guide/" + hint["guide"],
                "label": self.guide(hint["guide"])["titles"],
            }

        result["hints"] = (
            []
            if exam
            else [
                dict(guide_link(h), text=self.text(number, h["text"]))
                for h in quest["hints"][:hints]
            ]
        )
        result["facts"] = quest.get("facts", {})
        diagnostic_keys = (key for key in self.messages[number]["en"] if key.startswith("diagnostics."))
        result["diagnostics"] = {
            key.removeprefix("diagnostics."): self.text(number, key) for key in diagnostic_keys
        }
        if debrief:
            result["debrief"] = self.text(number, quest["debrief"])
            result["phrases"] = [self.text(number, key) for key in quest["phrases"]]
            result["questions"] = [
                self.question(self.messages[number], value, f"level.{number}.{index}")
                for index, value in enumerate(quest.get("questions", []))
            ]
            result["guides"] = list(
                {
                    hint.get("guide", hint.get("url")): guide_link(hint)
                    for hint in quest["hints"]
                }.values()
            )
        return result

    @staticmethod
    def question(messages, value, identity):
        if isinstance(value, str):
            return {
                "id": identity,
                "prompt": Resources.values(messages, value),
                "points": [],
            }
        return {
            "id": identity,
            "prompt": Resources.values(messages, value["prompt"]),
            "points": [Resources.values(messages, key) for key in value["points"]],
        }

    def interview(self, completed):
        groups = []
        for number in self.released:
            quest = self.quests[number]
            if (
                number not in completed
                or not quest.get("book")
                or not quest.get("questions")
            ):
                continue
            groups.append(
                {
                    "level": number,
                    "title": self.text(number, quest["title"]),
                    "book": {
                        **quest["book"],
                        "section": quest["book"].get("section")
                        or quest["book"].get("topic", ""),
                    },
                    "questions": [
                        self.question(
                            self.messages[number], value, f"level.{number}.{index}"
                        )
                        for index, value in enumerate(quest["questions"])
                    ],
                }
            )
        theory = [
            {
                "id": topic["id"],
                "title": Resources.values(self.interview_messages, topic["title"]),
                "book": topic["book"],
                "questions": [
                    self.question(
                        self.interview_messages, value, f"theory.{topic['id']}.{index}"
                    )
                    for index, value in enumerate(topic["questions"])
                ],
            }
            for topic in self.interview_topics
        ]
        return {"completed": groups, "theory": theory}

    def script(self, number, stage, name):
        if name not in {"setup", "check", "event"}:
            raise ValueError("Unknown script")
        path = self.root / "quests" / f"{number:03}" / f"{name}-{stage}.sh"
        return path.read_text() if path.exists() else "true\n"
