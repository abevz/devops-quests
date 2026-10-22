"""Regressions observed during review, without contacting any Docker daemon."""

import hashlib
import io
import json
import tarfile
from types import SimpleNamespace

import pytest

from devops_quests.oci import verified_config
from devops_quests.runtime import Runtime


def test_installations_keep_distinct_cluster_names_after_restart(tmp_path):
    first = Runtime(tmp_path / "first")
    second = Runtime(tmp_path / "second")
    assert first.cluster != second.cluster
    # Creating ownership metadata must not make a new installation look legacy.
    (first.state / "kind-owner").write_text(first.installation)
    assert Runtime(first.state).cluster == first.cluster


@pytest.mark.parametrize(
    "marker", ["kind-owner", "kind-node-id", "kind-admin.yaml", "kind.yaml"]
)
def test_legacy_cluster_name_is_preserved(tmp_path, marker):
    (tmp_path / marker).write_text("existing installation metadata")
    assert Runtime(tmp_path).cluster == "devops-quests"
    assert Runtime(tmp_path).cluster == "devops-quests"


def test_recorded_cluster_name_cannot_target_another_installation(tmp_path):
    runtime = Runtime(tmp_path)
    (tmp_path / "kind-cluster-name").write_text("devops-quests-foreign")
    with pytest.raises(RuntimeError, match="Invalid installation cluster name"):
        Runtime(runtime.state)


def result(stdout="", code=0):
    return SimpleNamespace(returncode=code, stdout=stdout, stderr="")


def archive_fixture(path):
    config = b'{"architecture":"amd64","os":"linux"}'
    config_id = "sha256:" + hashlib.sha256(config).hexdigest()
    manifest = json.dumps({"config": {"digest": config_id}, "layers": []}).encode()
    manifest_id = "sha256:" + hashlib.sha256(manifest).hexdigest()
    index = json.dumps({"manifests": [{"digest": manifest_id}]}).encode()
    with tarfile.open(path, "w") as archive:
        for name, content in {
            "index.json": index,
            "blobs/sha256/" + manifest_id[7:]: manifest,
            "blobs/sha256/" + config_id[7:]: config,
        }.items():
            info = tarfile.TarInfo(name)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))
    return config_id, manifest_id


def test_pending_pods_without_status_do_not_break_live_topology(tmp_path, monkeypatch):
    runtime = Runtime(tmp_path)
    monkeypatch.setattr(runtime, "inspect", lambda name: {"State": {"Running": True}})

    def kube(*args, **kwargs):
        if "pods" in args:
            return result(
                json.dumps(
                    {
                        "items": [
                            {"metadata": {"name": "just-admitted"}, "status": {}},
                            {"metadata": {"name": "no-status"}},
                        ]
                    }
                )
            )
        return result('{"items":[]}')

    monkeypatch.setattr(runtime, "kube", kube)
    nodes = runtime.topology({"id": "1" * 24, "level": 1})
    assert {
        x["name"]: x["state"]
        for x in nodes
        if x["name"] in {"just-admitted", "no-status"}
    } == {"just-admitted": "Pending", "no-status": "Pending"}


def test_teardown_and_reset_remove_per_bay_credentials_only(tmp_path, monkeypatch):
    runtime = Runtime(tmp_path)
    monkeypatch.setattr(runtime, "inspect", lambda name: None)

    def docker(*args, **kwargs):
        return result(code=1 if "inspect" in args else 0)

    monkeypatch.setattr(runtime, "docker", docker)
    progress = tmp_path / "progress.db"
    progress.write_bytes(b"preserve progress")
    bay = tmp_path / "bays" / ("1" * 24)
    bay.mkdir(parents=True)
    (bay / "id_ed25519").write_text("synthetic private key")
    (bay / "vault-init.json").write_text("synthetic unseal material")
    runtime.teardown({"id": "1" * 24, "level": 2})
    assert not bay.exists() and progress.read_bytes() == b"preserve progress"
    for identifier in ("2" * 24, "3" * 24):
        path = tmp_path / "bays" / identifier
        path.mkdir()
        (path / "canary").write_text("ephemeral")
    runtime.reset()
    assert list((tmp_path / "bays").iterdir()) == [] and progress.exists()


def test_bay_cleanup_refuses_path_traversal_and_foreign_symlink(tmp_path):
    runtime = Runtime(tmp_path / "state")
    outside = tmp_path / "outside"
    outside.mkdir()
    canary = outside / "keep"
    canary.write_text("keep")
    (runtime.state / "bays").mkdir()
    (runtime.state / "bays" / ("1" * 24)).symlink_to(outside, target_is_directory=True)
    for identifier in ("../outside", "1" * 24):
        with pytest.raises(RuntimeError):
            runtime.remove_bay_files({"id": identifier})
    assert canary.read_text() == "keep"


def test_oci_import_rejects_wrong_graph_before_subprocess(tmp_path, monkeypatch):
    path = tmp_path / "image.tar"
    config, manifest = archive_fixture(path)
    assert verified_config(path, manifest) == config
    with pytest.raises(ValueError, match="pinned manifest"):
        verified_config(path, "sha256:" + "0" * 64)
    runtime = Runtime(tmp_path / "runtime")
    runtime.root = tmp_path
    runtime.images = {"app": "docker.io/example@sha256:" + "0" * 64}
    (tmp_path / ".state").mkdir()
    path.rename(tmp_path / ".state/app-oci.tar")

    def forbidden(*args, **kwargs):
        pytest.fail("Invalid OCI graph reached Docker")

    monkeypatch.setattr("devops_quests.runtime.subprocess.run", forbidden)
    with pytest.raises(ValueError, match="pinned manifest"):
        runtime.load_image("app")


def test_oci_import_rejects_unrelated_cri_identity(tmp_path, monkeypatch):
    runtime = Runtime(tmp_path / "runtime")
    runtime.root = tmp_path
    (tmp_path / ".state").mkdir()
    _config, manifest = archive_fixture(tmp_path / ".state/app-oci.tar")
    runtime.images = {"app": "docker.io/example:1@" + manifest}
    monkeypatch.setattr(
        "devops_quests.runtime.subprocess.run",
        lambda *a, **kw: SimpleNamespace(returncode=0, stdout=b"", stderr=b""),
    )

    def docker(*args, **kwargs):
        if "inspecti" in args:
            return result(json.dumps({"status": {"id": "sha256:" + "0" * 64}}))
        return result("docker.io/example@" + manifest + "\n")

    monkeypatch.setattr(runtime, "docker", docker)
    with pytest.raises(RuntimeError, match="CRI image differs"):
        runtime.load_image("app")


def test_null_endpointslice_is_an_unavailable_service_not_a_topology_error(
    tmp_path, monkeypatch
):
    runtime = Runtime(tmp_path)
    monkeypatch.setattr(runtime, "inspect", lambda name: {"State": {"Running": True}})

    def kube(*args, **kwargs):
        if "endpointslices" in args:
            return result(
                json.dumps(
                    {
                        "items": [
                            {
                                "metadata": {
                                    "labels": {"kubernetes.io/service-name": "board"}
                                },
                                "endpoints": None,
                            }
                        ]
                    }
                )
            )
        return result('{"items":[]}')

    monkeypatch.setattr(runtime, "kube", kube)
    nodes = runtime.topology({"id": "1" * 24, "level": 1})
    assert (
        next(n for n in nodes if n["id"] == "service-board")["state"] == "NoEndpoints"
    )
