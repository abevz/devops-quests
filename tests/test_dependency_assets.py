import hashlib
import io
import json
import tarfile
import urllib.error

import pytest

from scripts import build_release, dependency_assets, prepare_assets


def sha(payload):
    return hashlib.sha256(payload).hexdigest()


def test_ordered_sources_fallback_and_checksum_failure(monkeypatch):
    calls = []

    def fetch(url, **kwargs):
        calls.append(url)
        if url == "https://mirror/asset":
            raise urllib.error.URLError("unavailable")
        return io.BytesIO(b"original bytes")

    monkeypatch.setattr(dependency_assets.urllib.request, "urlopen", fetch)
    item = {
        "urls": ["https://mirror/asset", "https://upstream/asset"],
        "sha256": sha(b"original bytes"),
    }
    assert dependency_assets.download("collection", item) == b"original bytes"
    assert calls == item["urls"]
    item["sha256"] = "0" * 64
    with pytest.raises(RuntimeError) as error:
        dependency_assets.download("collection", item)
    assert all(url in str(error.value) for url in item["urls"])
    assert "sha256 mismatch" in str(error.value)


def test_wrong_mirror_bytes_are_never_accepted(monkeypatch):
    monkeypatch.setattr(
        dependency_assets.urllib.request,
        "urlopen",
        lambda url, **kw: io.BytesIO(b"bad" if "mirror" in url else b"good"),
    )
    assert (
        dependency_assets.download(
            "asset",
            {"urls": ["https://mirror", "https://upstream"], "sha256": sha(b"good")},
        )
        == b"good"
    )


def test_install_release_uses_only_local_tools_collections_and_ghcr(
    tmp_path, monkeypatch
):
    from scripts.bootstrap import TOOLS

    monkeypatch.setattr(prepare_assets, "ROOT", tmp_path)
    (tmp_path / "labs").mkdir()
    (tmp_path / "bin").mkdir()
    state = tmp_path / ".state"
    state.mkdir()
    tools = {}
    for name in TOOLS:
        (tmp_path / "bin" / name).write_bytes(b"verified binary")
        tools[name] = {"binary_sha256": sha(b"verified binary")}
    (tmp_path / "tools.lock.json").write_text(json.dumps(tools))
    name = "collection.tar.gz"
    (state / name).write_bytes(b"collection")
    (tmp_path / "labs/collections.lock.json").write_text(
        json.dumps(
            {
                name: {
                    "sha256": sha(b"collection"),
                    "urls": ["https://galaxy.ansible.com/fail"],
                }
            }
        )
    )
    keys = {
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
    digest = "sha256:" + "a" * 64
    refs = {key: "docker.io/example/" + key + "@" + digest for key in keys | {"kind"}}
    (tmp_path / "images.lock.json").write_text(json.dumps(refs))
    (tmp_path / "labs/images.lock.json").write_text("{}")
    images = {
        key: {
            "reference": "ghcr.io/abevz/devops-quests-"
            + key.replace("_", "-")
            + "@"
            + digest
        }
        for key in keys
    }
    images["private"]["runtimeReference"] = (
        "docker.io/devops-quests/private-parcel@" + digest
    )
    calls = []

    def run(*args, **kwargs):
        calls.append(args)
        if args[0].endswith("/crane"):
            layout = __import__("pathlib").Path(args[3])
            layout.mkdir()
            (layout / "index.json").write_text(
                json.dumps({"manifests": [{"digest": digest}]})
            )
        else:
            assert args[:5] == (
                *prepare_assets.DOCKER,
                "pull",
                "--platform=linux/amd64",
            )
            assert args[5].startswith("ghcr.io/abevz/devops-quests-")

    monkeypatch.setattr(prepare_assets, "run", run)
    monkeypatch.setattr(
        prepare_assets.subprocess, "check_output", lambda *a, **kw: digest + "\n"
    )
    monkeypatch.setattr(
        dependency_assets.urllib.request,
        "urlopen",
        lambda *a, **kw: pytest.fail("Release preparation attempted HTTP download"),
    )
    prepare_assets.install_release({"images": images})
    assert calls and (state / name).read_bytes() == b"collection"
    assert (state / "app-oci.tar").is_file()
    (state / name).write_bytes(b"corrupted")
    with pytest.raises(RuntimeError, match="checksum"):
        prepare_assets.install_release({"images": images})
    (state / name).write_bytes(b"collection")
    (tmp_path / "bin/kind").unlink()
    with pytest.raises(RuntimeError, match="Release tool"):
        prepare_assets.install_release({"images": images})


def test_dependency_packaging_checks_original_bytes(tmp_path, monkeypatch):
    monkeypatch.setattr(build_release, "ROOT", tmp_path)
    for name in ("bin", "labs", ".state", ".ci-cache/wheelhouse", "dist"):
        (tmp_path / name).mkdir(parents=True)
    (tmp_path / "bin/tool").write_bytes(b"tool")
    (tmp_path / "tools.lock.json").write_text(
        json.dumps({"tool": {"binary_sha256": sha(b"tool")}})
    )
    (tmp_path / ".state/collection.tar.gz").write_bytes(b"collection")
    (tmp_path / "labs/collections.lock.json").write_text(
        json.dumps({"collection.tar.gz": {"sha256": sha(b"collection")}})
    )
    (tmp_path / ".ci-cache/wheelhouse/example.whl").write_bytes(b"wheel")
    assets = build_release.dependencies(tmp_path / "dist")
    assert assets["collection.tar.gz"] == sha(b"collection")
    with tarfile.open(
        tmp_path / "dist/devops-quests-dependencies-linux-amd64.tar.gz"
    ) as archive:
        assert set(archive.getnames()) == {"bin/tool", "wheelhouse/example.whl"}
    (tmp_path / "bin/tool").write_bytes(b"changed")
    with pytest.raises(RuntimeError, match="checksum"):
        build_release.dependencies(tmp_path / "dist")


def test_release_build_refuses_changed_image_inputs(tmp_path, monkeypatch):
    monkeypatch.setattr(prepare_assets, "ROOT", tmp_path)
    (tmp_path / "Dockerfile").write_bytes(b"changed")
    (tmp_path / "build-images.lock.json").write_text(
        json.dumps({"inputs": {"Dockerfile": sha(b"original")}})
    )
    with pytest.raises(RuntimeError, match="build input changed"):
        prepare_assets.release_build()


def test_release_download_never_falls_back_to_third_party(monkeypatch):
    calls = []

    def fetch(url, **kwargs):
        calls.append(url)
        raise urllib.error.URLError("mirror unavailable")

    monkeypatch.setattr(dependency_assets.urllib.request, "urlopen", fetch)
    mirror = "https://github.com/abevz/devops-quests/releases/download/deps-1/asset"
    with pytest.raises(RuntimeError, match="mirror unavailable"):
        dependency_assets.download(
            "asset",
            {"urls": [mirror, "https://galaxy.ansible.com/asset"], "sha256": "0" * 64},
            project_only=True,
        )
    assert calls == [mirror]
