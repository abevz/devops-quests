"""Install the complete offline curriculum beside the Python package."""

from pathlib import Path
from setuptools import setup

root = Path(__file__).parent
folders = (
    "docs",
    "quests",
    "solutions",
    "labs",
    "locales",
    "web",
    "scripts",
    "images",
    "vendor",
    "deploy",
    "devops_quests",
)
excluded = {"__pycache__", ".pytest_cache"}
groups = {}
for folder in folders:
    for path in (root / folder).rglob("*"):
        if (
            not path.is_file()
            or excluded.intersection(path.parts)
            or path.suffix == ".pyc"
        ):
            continue
        relative = path.relative_to(root)
        groups.setdefault(
            str(Path("share/devops-quests") / relative.parent), []
        ).append(str(relative))
for name in (
    "levels.yaml",
    "images.lock.json",
    "tools.lock.json",
    "pyproject.toml",
    "README.md",
    "LICENSE",
    "NOTICE",
    "THIRD_PARTY_NOTICES.md",
    "release-images.lock.json",
):
    if (root / name).is_file():
        groups.setdefault("share/devops-quests", []).append(name)
setup(data_files=sorted(groups.items()))
