"""A private pull must not turn the public fixture into a credentialed image."""

import hashlib
import importlib.util
import io
import json
import tarfile

from devops_quests.catalog import ROOT


def test_private_identity_is_distinct_deterministic_and_keeps_layers(tmp_path):
    spec = importlib.util.spec_from_file_location(
        "private_image", ROOT / "scripts/derive_private_image.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    def digest(value):
        return "sha256:" + hashlib.sha256(value).hexdigest()

    layer = b"fixture-layer"
    config = json.dumps(
        {"architecture": "amd64", "os": "linux", "config": {"Cmd": ["sleep", "20"]}}
    ).encode()
    manifest = json.dumps(
        {
            "schemaVersion": 2,
            "mediaType": "application/vnd.oci.image.manifest.v1+json",
            "config": {
                "mediaType": "application/vnd.oci.image.config.v1+json",
                "digest": digest(config),
                "size": len(config),
            },
            "layers": [
                {
                    "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
                    "digest": digest(layer),
                    "size": len(layer),
                }
            ],
        }
    ).encode()
    source = tmp_path / "source.tar"
    with tarfile.open(source, "w") as archive:
        for data in (config, manifest, layer):
            item = tarfile.TarInfo("blobs/sha256/" + digest(data).split(":")[1])
            item.size = len(data)
            archive.addfile(item, io.BytesIO(data))
    first = tmp_path / "first.tar"
    second = tmp_path / "second.tar"
    ref = "example.invalid/public:1@" + digest(manifest)
    a = module.derive(source, first, ref)
    b = module.derive(source, second, ref)
    assert a == b and first.read_bytes() == second.read_bytes()
    assert a["config_digest"] != digest(config) and a["reference"] != ref
    with tarfile.open(first) as archive:
        index = json.load(archive.extractfile("index.json"))
        desc = index["manifests"][0]
        new_manifest = json.load(
            archive.extractfile("blobs/sha256/" + desc["digest"].split(":")[1])
        )
        new_config = json.load(
            archive.extractfile("blobs/sha256/" + a["config_digest"].split(":")[1])
        )
    assert new_manifest["layers"][0]["digest"] == digest(layer)
    assert (
        new_config["config"]["Labels"]["org.opencontainers.image.version"]
        == "private-parcel-0.1.0"
    )
    assert new_config["config"]["Cmd"] == ["sleep", "20"]
