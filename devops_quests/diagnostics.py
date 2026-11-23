"""Validation for diagnostic guide links and author-defined dependencies."""
from graphlib import CycleError, TopologicalSorter
import re


LINK = re.compile(r"\[[^\]\n]+\]\(guides#guide=([a-z0-9.-]+)&section=([a-z][a-z0-9-]*)\)")
SECTION = re.compile(r"^#{2,6}[ \t]+.+[ \t]+\{#([a-z][a-z0-9-]*)\}[ \t]*$")
FENCE = re.compile(r"^[ \t]{0,3}(?:>\s*)?(`{3,}|~{3,})(.*)$")


def guide_sections(markdown):
    """Yield public section IDs outside fenced code."""
    fence = ""
    for line in markdown.splitlines():
        if match := FENCE.match(line):
            current = match[1]
            if not fence:
                fence = current
            elif current[0] == fence[0] and len(current) >= len(fence) and not match[2].strip():
                fence = ""
        elif not fence and (match := SECTION.fullmatch(line)):
            yield match[1]


def diagnostic_destination(text):
    """Return a cause's guide and section or report invalid diagnostic prose."""
    links = list(LINK.finditer(text))
    if len(links) != 1 or text[links[0].end():].strip():
        raise ValueError("Expected one guide section link at the end")
    if not text[:links[0].start()].strip():
        raise ValueError("Expected a cause before the guide section link")
    return links[0].groups()


def validate_dependencies(value, diagnostic_keys):
    """Check the declared prerequisite graph against the quest's diagnostic keys."""
    if not isinstance(value, dict):
        raise ValueError("Expected a mapping from diagnostic keys to prerequisites")
    for key, prerequisites in value.items():
        if key not in diagnostic_keys:
            raise ValueError(f"Unknown diagnostic key {key!r}")
        if not isinstance(prerequisites, list) or not prerequisites:
            raise ValueError(f"Expected a non-empty prerequisite list for {key!r}")
        if any(not isinstance(parent, str) or parent not in diagnostic_keys for parent in prerequisites):
            raise ValueError(f"Unknown prerequisite in the list for {key!r}")
        if len(prerequisites) != len(set(prerequisites)):
            raise ValueError(f"Duplicate prerequisite for {key!r}")
    try:
        TopologicalSorter(value).prepare()
    except CycleError as error:
        raise ValueError("Cyclic diagnostic prerequisites") from error
