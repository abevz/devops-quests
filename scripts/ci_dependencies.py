"""Restore hash-pinned CI package caches from the dependency GitHub Release."""

import json
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def restore():
    from scripts.dependency_assets import download

    lock = json.loads((ROOT / "ci-dependencies.lock.json").read_text())
    import hashlib

    if (
        hashlib.sha256((ROOT / "package-lock.json").read_bytes()).hexdigest()
        != lock["package_lock_sha256"]
    ):
        raise RuntimeError("npm lock changed; refresh the pinned dependency snapshot")
    cache = ROOT / ".ci-cache"
    cache.mkdir(exist_ok=True)
    for name, item in lock["assets"].items():
        payload = download(name, item)
        with tempfile.TemporaryFile() as stream:
            stream.write(payload)
            stream.seek(0)
            with tarfile.open(fileobj=stream) as archive:
                for member in archive.getmembers():
                    path = Path(member.name)
                    if (
                        path.is_absolute()
                        or ".." in path.parts
                        or path.parts[0] not in {"wheelhouse", "npm"}
                        or not (member.isfile() or member.isdir())
                    ):
                        raise RuntimeError(
                            "Unsafe CI dependency member: " + member.name
                        )
                archive.extractall(cache, filter="data")


if __name__ == "__main__":
    restore()
