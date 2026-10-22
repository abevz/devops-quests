"""Verified local asset cache; excludes all user/runtime state."""

import hashlib
import json
import re
import subprocess
from pathlib import Path

INPUTS = (
    "images.lock.json",
    "tools.lock.json",
    "labs/images.lock.json",
    "labs/collections.lock.json",
    "scripts/bootstrap.py",
    "scripts/lab_assets.py",
    "scripts/derive_private_image.py",
    "scripts/prepare_assets.py",
    "scripts/asset_cache.py",
)


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def inputs(root):
    names = list(INPUTS)
    for folder in ("images", "labs/images"):
        names.extend(
            str(p.relative_to(root)) for p in (root / folder).rglob("*") if p.is_file()
        )
    lock = root / "release-images.lock.json"
    if lock.exists():
        names.append(lock.name)
    return {name: digest(root / name) for name in sorted(names)}


def image_id(reference):
    return subprocess.check_output(
        [
            "docker",
            "--host",
            "unix:///var/run/docker.sock",
            "image",
            "inspect",
            reference,
            "--format={{.Id}}",
        ],
        text=True,
        stderr=subprocess.DEVNULL,
    ).strip()


def valid(root):
    try:
        receipt = json.loads((root / ".state/assets-ready.json").read_text())
        if receipt["inputs"] != inputs(root):
            return False
        for name, checksum in receipt["files"].items():
            relative = Path(name)
            if (
                len(relative.parts) != 2
                or relative.parts[0] not in {".state", "bin"}
                or relative.parts[1] in {"runtime", "assets-ready.json"}
                or (root / relative).is_symlink()
                or digest(root / relative) != checksum
            ):
                return False
        return len(receipt["images"]) == 7 and all(
            re.fullmatch(r"sha256:[a-f0-9]{64}", ref) and image_id(ref) == ref
            for ref in receipt["images"]
        )
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError):
        return False


def record(root):
    state = root / ".state"
    refs = json.loads((root / "images.lock.json").read_text())
    overrides = state / "host-images.json"
    host = (
        json.loads(overrides.read_text())
        if overrides.exists()
        else {
            key: image_id(refs[key]) for key in ("dind", "gitea", "vault", "registry")
        }
    )
    overrides.write_text(json.dumps(host, indent=2) + "\n")
    overrides.chmod(0o600)
    ids = list(host.values()) + [
        json.loads((state / name).read_text())["id"]
        for name in ("built-image.json", "kind-image.json")
    ]
    ids.append(json.loads((state / "lab-images.json").read_text())["diagnostic"]["id"])
    files = [
        p
        for p in state.iterdir()
        if p.is_file()
        and (p.suffix in {".tar", ".ref", ".json"} or p.name.endswith(".tar.gz"))
        and p.name != "assets-ready.json"
    ]
    files.extend(
        root / "bin" / name
        for name in json.loads((root / "tools.lock.json").read_text())
    )
    receipt = {
        "inputs": inputs(root),
        "files": {str(p.relative_to(root)): digest(p) for p in sorted(files)},
        "images": ids,
    }
    path = state / "assets-ready.json"
    path.write_text(json.dumps(receipt, indent=2) + "\n")
    path.chmod(0o600)
