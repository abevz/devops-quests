"""Prepare pinned Lab-only images before starting the offline workspaces."""

import hashlib
import json
import os
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCKER = ["docker", "--host", "unix:///var/run/docker.sock"]


def main():
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
        with urllib.request.urlopen(asset["url"], timeout=60) as response:
            content = response.read(4 * 1024 * 1024)
        if hashlib.sha256(content).hexdigest() != asset["sha256"]:
            raise RuntimeError("Collection checksum mismatch: " + name)
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
    identifier = subprocess.run(
        [*DOCKER, "image", "inspect", tag, "--format={{.Id}}"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    (state / "lab-images.json").write_text(
        json.dumps({"diagnostic": {"tag": tag, "id": identifier}}, indent=2) + "\n"
    )
    print("Lab image assets prepared; no workspace or application was started.")


if __name__ == "__main__":
    main()
