#!/usr/bin/env python3
"""Verify separate built-image archives and resolve legacy/containerd IDs."""

import argparse
import hashlib
import json
import subprocess
import tarfile
from pathlib import Path


def archive_identity(path, expected_config):
    with tarfile.open(path) as archive:
        index = json.load(archive.extractfile("index.json"))
        if len(index["manifests"]) != 1:
            raise ValueError("Expected one image per transport archive")
        manifest_id = index["manifests"][0]["digest"]
        raw = archive.extractfile(
            "blobs/sha256/" + manifest_id.removeprefix("sha256:")
        ).read()
        if "sha256:" + hashlib.sha256(raw).hexdigest() != manifest_id:
            raise ValueError("Transport manifest digest mismatch")
        manifest = json.loads(raw)
        if manifest["config"]["digest"] != expected_config:
            raise ValueError("Transport image config differs from verified build")
        config = archive.extractfile(
            "blobs/sha256/" + expected_config.removeprefix("sha256:")
        ).read()
        if "sha256:" + hashlib.sha256(config).hexdigest() != expected_config:
            raise ValueError("Transport config content digest mismatch")
    return manifest_id


def import_image(archive, metadata):
    original = json.loads(metadata.read_text())
    expected = original.get("source_config_id", original["id"])
    manifest = archive_identity(archive, expected)
    docker = ["docker", "--host", "unix:///var/run/docker.sock"]
    subprocess.run([*docker, "load", "--input", str(archive)], check=True)
    actual = None
    for reference in (manifest, expected):
        result = subprocess.run(
            [*docker, "image", "inspect", reference],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            actual = json.loads(result.stdout)[0]["Id"]
            break
    if actual not in {manifest, expected}:
        raise RuntimeError("Loaded image identity could not be verified")
    original.update(id=actual, source_config_id=expected, transport_manifest=manifest)
    metadata.write_text(json.dumps(original) + "\n")
    metadata.chmod(0o600)
    return {"source_config": expected, "runtime_id": actual, "manifest": manifest}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--archives", type=Path, required=True)
    args = parser.parse_args()
    result = {}
    for name, filename in (("built", "built-image.json"), ("kind", "kind-image.json")):
        result[name] = import_image(
            args.archives / ("devops-quests-" + name + "-image.tar"),
            args.state / filename,
        )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
