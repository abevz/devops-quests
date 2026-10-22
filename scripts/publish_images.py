"""Release-CI only: publish built/mirrored images and emit their exact digest lock."""

import argparse
import json
import os
import re
import subprocess
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCKER = ["docker", "--host", "unix:///var/run/docker.sock"]


def command(*args):
    return subprocess.check_output(list(args), text=True).strip()


def publish(version):
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?", version):
        raise ValueError("Expected immutable tag")
    if (
        os.environ.get("GITHUB_ACTIONS") != "true"
        or os.environ.get("GITHUB_REF") != "refs/tags/" + version
        or os.environ.get("GITHUB_REPOSITORY") != "abevz/devops-quests"
    ):
        raise RuntimeError(
            "Image publication is restricted to this repository's tag workflow"
        )
    crane = str(ROOT / "bin/crane")
    images = {}
    upstream = json.loads((ROOT / "images.lock.json").read_text())
    upstream.update(json.loads((ROOT / "labs/images.lock.json").read_text()))
    for key in (
        "app",
        "argocd",
        "redis",
        "coredns",
        "traefik",
        "metrics",
        "prometheus",
        "lab_tools",
        "lab_nginx",
        "dind",
        "gitea",
        "vault",
        "registry",
    ):
        target = "ghcr.io/abevz/devops-quests-" + key.replace("_", "-") + ":" + version
        # OCI archives use platform-specific manifests; outer Docker services
        # may retain a multi-platform upstream index. Always pin what was pushed.
        args = [crane, "copy", upstream[key], target]
        if key not in {"dind", "gitea", "vault", "registry"}:
            args += ["--platform=linux/amd64"]
        subprocess.run(args, check=True)
        digest = command(crane, "digest", target)
        if (
            key not in {"dind", "gitea", "vault", "registry"}
            and digest != upstream[key].split("@", 1)[1]
        ):
            raise RuntimeError("Mirror digest changed: " + key)
        images[key] = {
            "reference": target.split(":", 1)[0] + "@" + digest,
            "source": upstream[key],
        }
    state = ROOT / ".state"
    built = {
        "workstation": json.loads((state / "built-image.json").read_text())["id"],
        "kind_built": json.loads((state / "kind-image.json").read_text())["id"],
        "diagnostic": json.loads((state / "lab-images.json").read_text())["diagnostic"][
            "id"
        ],
    }
    for key, identifier in built.items():
        target = "ghcr.io/abevz/devops-quests-" + key.replace("_", "-") + ":" + version
        subprocess.run([*DOCKER, "tag", identifier, target], check=True)
        subprocess.run([*DOCKER, "push", target], check=True)
        images[key] = {
            "reference": target.split(":", 1)[0]
            + "@"
            + command(crane, "digest", target)
        }
    with tempfile.TemporaryDirectory(prefix="release-private-") as tmp:
        layout = Path(tmp)
        with tarfile.open(state / "private-oci.tar") as tar:
            tar.extractall(layout, filter="data")
        descriptor = json.loads((layout / "index.json").read_text())["manifests"][0]
        target = "ghcr.io/abevz/devops-quests-private:" + version
        subprocess.run([crane, "push", str(layout), target], check=True)
        digest = command(crane, "digest", target)
        if digest != descriptor["digest"]:
            raise RuntimeError("Private fixture digest changed")
        images["private"] = {
            "reference": target.split(":", 1)[0] + "@" + digest,
            "runtimeReference": descriptor["annotations"][
                "org.opencontainers.image.ref.name"
            ],
        }
    lock = {
        "version": version,
        "commit": command("git", "-C", str(ROOT), "rev-parse", "HEAD"),
        "platform": "linux/amd64",
        "images": images,
    }
    (ROOT / "release-images.lock.json").write_text(json.dumps(lock, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    publish(parser.parse_args().version)
