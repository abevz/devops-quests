"""A store change may alter runtime IDs, but must never change verified content."""

import hashlib
import importlib.util
import io
import json
import tarfile
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location(
    "image_transport", Path(__file__).parents[1] / "deploy/import_built_images.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def fixture(path, *, tampered=False):
    config = json.dumps({"architecture": "amd64", "os": "linux"}).encode()
    config_id = "sha256:" + hashlib.sha256(config).hexdigest()
    manifest = json.dumps({"config": {"digest": config_id}, "layers": []}).encode()
    manifest_id = "sha256:" + hashlib.sha256(manifest).hexdigest()
    index = json.dumps({"manifests": [{"digest": manifest_id}]}).encode()
    members = {
        "index.json": index,
        "blobs/sha256/" + manifest_id[7:]: manifest + (b" " if tampered else b""),
        "blobs/sha256/" + config_id[7:]: config,
    }
    with tarfile.open(path, "w") as archive:
        for name, content in members.items():
            info = tarfile.TarInfo(name)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))
    return config_id, manifest_id


def test_transport_binds_manifest_to_the_verified_config(tmp_path):
    path = tmp_path / "image.tar"
    config, manifest = fixture(path)
    assert module.archive_identity(path, config) == manifest
    with pytest.raises(ValueError, match="differs from verified build"):
        module.archive_identity(path, "sha256:" + "0" * 64)


def test_modified_manifest_is_rejected_before_docker_load(tmp_path, monkeypatch):
    path = tmp_path / "image.tar"
    config, _ = fixture(path, tampered=True)
    metadata = tmp_path / "built-image.json"
    metadata.write_text(json.dumps({"id": config}))

    def forbidden(*args, **kwargs):
        pytest.fail("Docker must not be called for a corrupt transport")

    monkeypatch.setattr(module.subprocess, "run", forbidden)
    with pytest.raises(ValueError, match="manifest digest mismatch"):
        module.import_image(path, metadata)
    assert json.loads(metadata.read_text()) == {"id": config}
