"""Deterministic private fixture identity, without weakening pull authentication."""

import hashlib
import io
import json
import tarfile
from pathlib import Path


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def derive(source, destination, source_ref):
    with tarfile.open(source) as archive:
        members = {
            item.name: archive.extractfile(item).read()
            for item in archive
            if item.isfile()
        }
    digest = source_ref.split("@", 1)[1]
    original = members["blobs/sha256/" + digest.split(":", 1)[1]]
    if "sha256:" + hashlib.sha256(original).hexdigest() != digest:
        raise ValueError("Source manifest does not match its pinned digest")
    manifest = json.loads(original)
    config_path = "blobs/sha256/" + manifest["config"]["digest"].split(":", 1)[1]
    config = json.loads(members[config_path])
    config.setdefault("config", {}).setdefault("Labels", {}).update(
        {
            "devops-quests": "true",
            "org.opencontainers.image.version": "private-parcel-0.1.0",
        }
    )
    config_bytes = encoded(config)
    config_digest = "sha256:" + hashlib.sha256(config_bytes).hexdigest()
    manifest["config"].update(digest=config_digest, size=len(config_bytes))
    manifest_bytes = encoded(manifest)
    manifest_digest = "sha256:" + hashlib.sha256(manifest_bytes).hexdigest()
    repository = "docker.io/devops-quests/private-parcel"
    reference = repository + ":0.1.0@" + manifest_digest
    index = {
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.index.v1+json",
        "manifests": [
            {
                "mediaType": manifest["mediaType"],
                "digest": manifest_digest,
                "size": len(manifest_bytes),
                "annotations": {
                    "org.opencontainers.image.ref.name": repository
                    + "@"
                    + manifest_digest
                },
            }
        ],
    }
    output = {
        "oci-layout": encoded({"imageLayoutVersion": "1.0.0"}),
        "index.json": encoded(index),
        "blobs/sha256/" + config_digest.split(":", 1)[1]: config_bytes,
        "blobs/sha256/" + manifest_digest.split(":", 1)[1]: manifest_bytes,
    }
    for layer in manifest["layers"]:
        path = "blobs/sha256/" + layer["digest"].split(":", 1)[1]
        payload = members[path]
        if "sha256:" + hashlib.sha256(payload).hexdigest() != layer["digest"]:
            raise ValueError("Layer digest mismatch")
        output[path] = payload
    destination = Path(destination)
    temporary = destination.with_suffix(".tmp")
    with tarfile.open(temporary, "w") as archive:
        for name, payload in sorted(output.items()):
            entry = tarfile.TarInfo(name)
            entry.size = len(payload)
            entry.mode = 0o644
            entry.mtime = 0
            archive.addfile(entry, io.BytesIO(payload))
    temporary.replace(destination)
    return {
        "reference": reference,
        "config_digest": config_digest,
        "source": source_ref,
        "version": "0.1.0",
        "purpose": "private registry fixture; distinct identity from public preloaded workloads",
    }


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    images = json.loads((root / "images.lock.json").read_text())
    result = derive(
        root / ".state/app-oci.tar", root / ".state/private-oci.tar", images["app"]
    )
    (root / "images.derived.lock.json").write_text(
        json.dumps({"private_app": result}, indent=2) + "\n"
    )
