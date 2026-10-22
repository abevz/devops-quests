import json
import shutil
import subprocess
import tarfile

import pytest

from devops_quests.catalog import ROOT
from devops_quests.runtime import Runtime
from scripts import build_release, publish_images


def test_release_excludes_untracked_files_and_records_executable_bits(
    tmp_path, monkeypatch
):
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    (tmp_path / "run.sh").write_text("#!/bin/sh\ntrue\n")
    (tmp_path / "run.sh").chmod(0o755)
    (tmp_path / "private.txt").write_text("not a publication input")
    bundles = tmp_path / "web/vendor"
    bundles.mkdir(parents=True)
    for name in ("terminal.js", "markdown.js", "mermaid.js", "locale.js", "xterm.css"):
        (bundles / name).write_text("generated bundle")
    subprocess.run(["git", "add", "run.sh"], cwd=tmp_path, check=True)
    subprocess.run(
        [
            "git",
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.test",
            "commit",
            "-qm",
            "Fixture",
        ],
        cwd=tmp_path,
        check=True,
    )
    monkeypatch.setattr(build_release, "ROOT", tmp_path)
    archive = build_release.build("v1.0.0", tmp_path / "dist")
    with tarfile.open(archive) as tar:
        assert "private.txt" not in tar.getnames()
        manifest = json.load(tar.extractfile("RELEASE.json"))
        assert manifest["files"]["run.sh"]["executable"]
        assert not manifest["files"]["web/vendor/terminal.js"]["executable"]
    (tmp_path / "release-images.lock.json").write_text(
        json.dumps({"version": "v0.0.0"})
    )
    with pytest.raises(ValueError, match="does not match"):
        build_release.build("v1.0.0", tmp_path / "dist")


def test_image_publication_refuses_local_invocation(monkeypatch):
    monkeypatch.delenv("GITHUB_ACTIONS", raising=False)
    with pytest.raises(RuntimeError, match="restricted"):
        publish_images.publish("v1.0.0")


def test_host_image_overrides_are_narrow_and_validated(tmp_path):
    for name in ("images.lock.json", "levels.yaml"):
        shutil.copy2(ROOT / name, tmp_path / name)
    assets = tmp_path / ".state"
    assets.mkdir()
    path = assets / "host-images.json"
    path.write_text(json.dumps({"gitea": "sha256:" + "a" * 64}))
    runtime = Runtime(assets / "runtime", root=tmp_path)
    assert runtime.images["gitea"] == "sha256:" + "a" * 64
    for invalid in ({"kind": "sha256:" + "a" * 64}, {"gitea": "latest"}, []):
        path.write_text(json.dumps(invalid))
        with pytest.raises(RuntimeError, match="Invalid release host-image"):
            Runtime(assets / "runtime", root=tmp_path)


def test_asset_receipt_rejects_modified_tool_or_missing_image(tmp_path, monkeypatch):
    from scripts import asset_cache
    import hashlib

    for name in asset_cache.INPUTS:
        target = tmp_path / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("{}")
    (tmp_path / "tools.lock.json").write_text(json.dumps({"tool": {}}))
    (tmp_path / "images.lock.json").write_text(
        json.dumps({k: k for k in ("dind", "gitea", "vault", "registry")})
    )
    state = tmp_path / ".state"
    state.mkdir()
    for name in ("built-image.json", "kind-image.json"):
        (state / name).write_text(
            json.dumps({"id": "sha256:" + hashlib.sha256(name.encode()).hexdigest()})
        )
    (state / "lab-images.json").write_text(
        json.dumps({"diagnostic": {"id": "sha256:" + "f" * 64}})
    )
    (tmp_path / "bin").mkdir()
    tool = tmp_path / "bin/tool"
    tool.write_text("verified tool")

    def identify(ref):
        return (
            ref
            if ref.startswith("sha256:")
            else "sha256:" + hashlib.sha256(ref.encode()).hexdigest()
        )

    monkeypatch.setattr(asset_cache, "image_id", identify)
    asset_cache.record(tmp_path)
    assert asset_cache.valid(tmp_path)
    tool.write_text("corrupted")
    assert not asset_cache.valid(tmp_path)
    tool.write_text("verified tool")
    monkeypatch.setattr(asset_cache, "image_id", lambda ref: "missing")
    assert not asset_cache.valid(tmp_path)
