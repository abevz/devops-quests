"""Fetch pinned dependency bytes from ordered sources, or verify local assets."""

import hashlib
import urllib.error
import urllib.request
from pathlib import Path


def verify(path, checksum):
    path = Path(path)
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
        raise RuntimeError("Dependency checksum mismatch or missing file: " + str(path))
    return path


def download(name, item, project_only=False):
    attempts = []
    urls = item["urls"]
    if project_only:
        urls = [
            url
            for url in urls
            if url.startswith(
                "https://github.com/abevz/devops-quests/releases/download/"
            )
        ]
        if not urls:
            raise RuntimeError("Missing project GitHub dependency source: " + name)
    for url in urls:
        try:
            with urllib.request.urlopen(url, timeout=90) as response:
                payload = response.read()
            if hashlib.sha256(payload).hexdigest() != item["sha256"]:
                raise RuntimeError("sha256 mismatch")
            return payload
        except (OSError, urllib.error.URLError, RuntimeError) as error:
            attempts.append(url + ": " + str(error))
    raise RuntimeError(
        "Cannot fetch " + name + "; attempted sources:\n" + "\n".join(attempts)
    )
