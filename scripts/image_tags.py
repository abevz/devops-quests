"""Local image names isolated by checkout path; runtime still uses image IDs."""

import hashlib
import os
import re
from pathlib import Path


def image_namespace(root, environ=None):
    """Return a stable repository component, or a validated explicit namespace."""
    environ = os.environ if environ is None else environ
    if "DQ_IMAGE_NAMESPACE" in environ:
        namespace = environ["DQ_IMAGE_NAMESPACE"]
        if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?", namespace):
            raise ValueError(
                "DQ_IMAGE_NAMESPACE must be 1–64 lowercase letters, digits or hyphens, starting and ending with a letter or digit"
            )
        return namespace
    path = Path(root).resolve()
    slug = re.sub(r"[^a-z0-9]+", "-", path.name.lower()).strip("-")[:40] or "checkout"
    identity = hashlib.sha256(str(path).encode()).hexdigest()[:12]
    return f"{slug}-{identity}"


def image_repository(root, name):
    return f"devops-quests/{image_namespace(root)}/{name}"


def image_tag(root, name, version):
    return f"{image_repository(root, name)}:{version}"


if __name__ == "__main__":
    print(image_namespace(Path(__file__).resolve().parents[1]))
