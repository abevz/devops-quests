"""Prepare pinned Lab-only images before starting the offline workspaces."""

import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
DOCKER = ["docker", "--host", "unix:///var/run/docker.sock"]
IMAGE_LOCK_DIR = Path("/tmp") / f"devops-quests-images-{os.getuid()}"


def diagnostic_id(tag):
    """Return an owned local image ID; an occupied foreign tag is an error."""
    found = subprocess.run(
        [
            *DOCKER,
            "image",
            "ls",
            "--quiet",
            "--no-trunc",
            "--filter",
            "reference=" + tag,
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if not found:
        return None
    image = json.loads(
        subprocess.run(
            [*DOCKER, "image", "inspect", tag, "--format={{json .}}"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    labels = image.get("Config", {}).get("Labels") or {}
    if labels.get("devops-quests.lab-asset") != "true":
        raise RuntimeError(
            f"Refusing to overwrite diagnostic tag without devops-quests.lab-asset=true: {tag}"
        )
    return image["Id"]


def diagnostic_image(source, state, tag):
    # Serialize cooperating worktrees so two absent-tag checks cannot both build.
    IMAGE_LOCK_DIR.mkdir(mode=0o700, exist_ok=True)
    with (IMAGE_LOCK_DIR / (tag.split(":")[1] + ".lock")).open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        identifier = diagnostic_id(tag)
        if identifier:
            return identifier
        with tempfile.TemporaryDirectory(prefix="lab-build-", dir=state) as directory:
            work = Path(directory)
            for path in source.iterdir():
                shutil.copyfile(path, work / path.name)
            subprocess.run(
                [
                    "go",
                    "build",
                    "-trimpath",
                    "-o",
                    str(work / "app"),
                    str(work / "main.go"),
                ],
                env=dict(
                    os.environ,
                    CGO_ENABLED="0",
                    GOOS="linux",
                    GOARCH="amd64",
                    GO111MODULE="off",
                ),
                check=True,
            )
            subprocess.run(
                [
                    *DOCKER,
                    "build",
                    "--network=none",
                    "--label",
                    "devops-quests.lab-asset=true",
                    "-t",
                    tag,
                    str(work),
                ],
                check=True,
            )
        identifier = diagnostic_id(tag)
        if not identifier:
            raise RuntimeError("Diagnostic build did not create its tag: " + tag)
        return identifier


def main():
    from scripts.dependency_assets import download

    state = ROOT / ".state"
    state.mkdir(exist_ok=True)
    for name, asset in json.loads(
        (ROOT / "labs/collections.lock.json").read_text()
    ).items():
        path = state / name
        if (
            path.is_file()
            and hashlib.sha256(path.read_bytes()).hexdigest() == asset["sha256"]
        ):
            continue
        content = download(name, asset)
        path.write_bytes(content)
    images = json.loads((ROOT / "labs/images.lock.json").read_text())
    for key, reference in images.items():
        archive = state / (key + "-oci.tar")
        marker = state / (key + "-oci.ref")
        if archive.is_file() and marker.is_file() and marker.read_text() == reference:
            continue
        with tempfile.TemporaryDirectory(prefix="lab-oci-", dir=state) as directory:
            layout = Path(directory) / "image"
            subprocess.run(
                [
                    str(ROOT / "bin/crane"),
                    "pull",
                    reference,
                    str(layout),
                    "--format=oci",
                    "--annotate-ref",
                    "--platform=linux/amd64",
                ],
                check=True,
            )
            index_path = layout / "index.json"
            index = json.loads(index_path.read_text())
            manifest = index["manifests"][0]
            if manifest["digest"] != reference.split("@", 1)[1]:
                raise RuntimeError("Lab image digest mismatch")
            manifest.setdefault("annotations", {})[
                "org.opencontainers.image.ref.name"
            ] = reference
            index_path.write_text(json.dumps(index))
            temporary = Path(directory) / "image.tar"
            with tarfile.open(temporary, "w") as output:
                for item in sorted(layout.iterdir()):
                    output.add(item, arcname=item.name)
            temporary.replace(archive)
        marker.write_text(reference)
    source = ROOT / "labs/images/diagnostic"
    digest = hashlib.sha256()
    for path in sorted(source.iterdir()):
        digest.update(path.name.encode())
        digest.update(path.read_bytes())
    tag = "dq-lab-diagnostic:" + digest.hexdigest()[:20]
    identifier = diagnostic_image(source, state, tag)
    (state / "lab-images.json").write_text(
        json.dumps({"diagnostic": {"tag": tag, "id": identifier}}, indent=2) + "\n"
    )
    print("Lab image assets prepared; no workspace or application was started.")


if __name__ == "__main__":
    main()
