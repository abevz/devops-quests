"""Validate the pinned single-image OCI graph before a sandbox import."""

import hashlib
import json
import tarfile


def verified_config(path, expected_manifest):
    with tarfile.open(path) as archive:
        index = json.load(archive.extractfile("index.json"))
        manifests = index["manifests"]
        if len(manifests) != 1 or manifests[0]["digest"] != expected_manifest:
            raise ValueError("OCI index does not identify the pinned manifest")

        def content(digest):
            if not digest.startswith("sha256:") or len(digest) != 71:
                raise ValueError("Unsupported OCI content digest")
            raw = archive.extractfile("blobs/sha256/" + digest[7:]).read()
            if "sha256:" + hashlib.sha256(raw).hexdigest() != digest:
                raise ValueError("OCI content digest mismatch")
            return raw

        manifest = json.loads(content(expected_manifest))
        config_id = manifest["config"]["digest"]
        content(config_id)
        return config_id
