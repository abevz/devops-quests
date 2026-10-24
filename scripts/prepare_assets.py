"""Prepare offline assets from pinned source or an immutable release image lock."""

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
DOCKER = ["docker", "--host", "unix:///var/run/docker.sock"]


def run(*args, **kwargs):
    return subprocess.run(list(args), check=True, **kwargs)


def tools_only(offline=False, project_only=False):
    from scripts.bootstrap import TOOLS
    from scripts.dependency_assets import download
    import io

    lock = json.loads((ROOT / "tools.lock.json").read_text())
    (ROOT / "bin").mkdir(exist_ok=True)
    for name, (_, _, member) in TOOLS.items():
        item = lock[name]
        target = ROOT / "bin" / name
        if (
            target.is_file()
            and hashlib.sha256(target.read_bytes()).hexdigest() == item["binary_sha256"]
        ):
            continue
        if offline:
            raise RuntimeError("Missing or corrupt Release tool: " + name)
        payload = download(
            name,
            {"urls": item["urls"], "sha256": item["download_sha256"]},
            project_only=project_only,
        )
        if member:
            with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
                payload = archive.extractfile(member).read()
        if hashlib.sha256(payload).hexdigest() != item["binary_sha256"]:
            raise RuntimeError("Pinned tool binary mismatch: " + name)
        target.write_bytes(payload)
        target.chmod(0o755)


def install_release(lock):
    state = ROOT / ".state"
    state.mkdir(mode=0o700, exist_ok=True)
    from scripts.dependency_assets import verify

    tools_only(offline=True)
    for name, item in json.loads(
        (ROOT / "labs/collections.lock.json").read_text()
    ).items():
        verify(state / name, item["sha256"])
    runtime_refs = json.loads((ROOT / "images.lock.json").read_text())
    runtime_refs.update(json.loads((ROOT / "labs/images.lock.json").read_text()))
    required = {
        "workstation",
        "kind_built",
        "diagnostic",
        "app",
        "argocd",
        "redis",
        "coredns",
        "traefik",
        "metrics",
        "prometheus",
        "private",
        "lab_tools",
        "lab_nginx",
        "dind",
        "gitea",
        "vault",
        "registry",
    }
    images = lock.get("images", {})
    if set(images) != required:
        raise ValueError("Incomplete release image lock")
    host_images = {}
    for key, item in images.items():
        reference = item["reference"]
        if not re.fullmatch(
            r"ghcr\.io/abevz/devops-quests-[a-z0-9-]+@sha256:[a-f0-9]{64}", reference
        ):
            raise ValueError("Image must have an immutable release digest: " + key)
        run(*DOCKER, "pull", "--platform=linux/amd64", reference)
        identifier = subprocess.check_output(
            [*DOCKER, "image", "inspect", reference, "--format={{.Id}}"], text=True
        ).strip()
        if key in {"dind", "gitea", "vault", "registry"}:
            host_images[key] = identifier
            continue
        if key in {"workstation", "kind_built", "diagnostic"}:
            name = {
                "workstation": "built-image.json",
                "kind_built": "kind-image.json",
                "diagnostic": "lab-images.json",
            }[key]
            value = {"id": identifier, "reference": reference}
            if key == "kind_built":
                value["upstream"] = runtime_refs["kind"]
            if key == "diagnostic":
                value = {"diagnostic": {"id": identifier, "tag": reference}}
            (state / name).write_text(json.dumps(value, indent=2) + "\n")
            continue
        alias = runtime_refs[key] if key != "private" else item["runtimeReference"]
        if key == "private" and not alias.startswith(
            "docker.io/devops-quests/private-parcel"
        ):
            raise ValueError("Unexpected private fixture runtime alias")
        with tempfile.TemporaryDirectory(dir=state, prefix="release-oci-") as tmp:
            layout = Path(tmp) / "image"
            run(
                str(ROOT / "bin/crane"),
                "pull",
                reference,
                str(layout),
                "--format=oci",
                "--annotate-ref",
                "--platform=linux/amd64",
            )
            index = json.loads((layout / "index.json").read_text())
            descriptor = index["manifests"][0]
            if descriptor["digest"] != reference.rsplit("@", 1)[1]:
                raise RuntimeError("Release image digest changed: " + key)
            # The offline exercises retain their original runtime aliases. A mirror
            # changes transport location, not the image manifest or exercise contract.
            if descriptor["digest"] != alias.rsplit("@", 1)[1]:
                raise RuntimeError("Mirror does not equal curriculum image: " + key)
            descriptor.setdefault("annotations", {})[
                "org.opencontainers.image.ref.name"
            ] = alias
            (layout / "index.json").write_text(json.dumps(index))
            with tarfile.open(state / (key + "-oci.tar"), "w") as archive:
                for path in sorted(layout.iterdir()):
                    archive.add(path, arcname=path.name)
        if key != "private":
            (state / (key + "-oci.ref")).write_text(alias)
    (state / "host-images.json").write_text(json.dumps(host_images, indent=2) + "\n")
    (state / "host-images.json").chmod(0o600)


def release_build():
    """Reuse immutable images only while all image-build inputs remain identical."""
    from scripts.dependency_assets import download

    lock = json.loads((ROOT / "build-images.lock.json").read_text())
    for name, checksum in lock["inputs"].items():
        if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != checksum:
            raise RuntimeError(
                "Image build input changed; refresh build-images.lock.json: " + name
            )
    tools_only(project_only=True)
    state = ROOT / ".state"
    state.mkdir(mode=0o700, exist_ok=True)
    for name, item in json.loads(
        (ROOT / "labs/collections.lock.json").read_text()
    ).items():
        path = state / name
        if (
            not path.is_file()
            or hashlib.sha256(path.read_bytes()).hexdigest() != item["sha256"]
        ):
            path.write_bytes(download(name, item, project_only=True))
    install_release(lock)


def main():
    from scripts import asset_cache

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", action="store_true")
    parser.add_argument("--release-build", action="store_true")
    parser.add_argument("--tools-only", action="store_true")
    parser.add_argument("--lock", type=Path, default=ROOT / "release-images.lock.json")
    args = parser.parse_args()
    if args.release_build:
        release_build()
    elif args.tools_only:
        tools_only()
    elif not args.source and asset_cache.valid(ROOT):
        print(
            "Verified local assets reused; no runtime/user state was imported.",
            flush=True,
        )
    elif args.source or not args.lock.is_file():
        tools_only()
        run(sys.executable, str(ROOT / "scripts/bootstrap.py"), cwd=ROOT)
        run(sys.executable, str(ROOT / "scripts/lab_assets.py"), cwd=ROOT)
    else:
        install_release(json.loads(args.lock.read_text()))
    if not args.tools_only:
        asset_cache.record(ROOT)


if __name__ == "__main__":
    main()
