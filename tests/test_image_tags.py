"""Source builds own tags by checkout; sandbox state continues to pin image IDs."""

import hashlib
import json
import re
import shutil
from types import SimpleNamespace

import pytest

from devops_quests.catalog import ROOT
from devops_quests.runtime import Runtime
from devops_quests.labs import LabCatalog
from scripts import bootstrap, lab_assets
from scripts.image_tags import image_namespace, image_tag


def test_namespace_is_stable_safe_and_path_specific(tmp_path):
    root = tmp_path / "Mixed Case_!"
    namespace = image_namespace(root, {})
    assert re.fullmatch(r"mixed-case-[a-f0-9]{12}", namespace)
    assert image_namespace(root / "child/..", {}) == namespace
    assert image_namespace(tmp_path / "other" / root.name, {}) != namespace
    assert image_namespace(tmp_path / "mixed-case", {}) != namespace
    assert image_namespace(tmp_path / ("a" * 200), {}).startswith("a" * 40 + "-")
    assert image_namespace(tmp_path / "!!!", {}).startswith("checkout-")


@pytest.mark.parametrize("override", ["preview", "dq-27", "9", "a" * 64])
def test_namespace_override_is_explicit_and_stable(tmp_path, override):
    assert image_namespace(tmp_path, {"DQ_IMAGE_NAMESPACE": override}) == override
    assert (
        image_namespace(tmp_path / "other", {"DQ_IMAGE_NAMESPACE": override})
        == override
    )


@pytest.mark.parametrize(
    "override", ["", "UPPER", "a/b", "a:b", "a_b", "-start", "end-", "a" * 65, " space"]
)
def test_unsafe_namespace_override_is_rejected(tmp_path, override):
    with pytest.raises(ValueError, match="DQ_IMAGE_NAMESPACE"):
        image_namespace(tmp_path, {"DQ_IMAGE_NAMESPACE": override})


def fake_docker(monkeypatch, module, images=None):
    calls = []
    images = {} if images is None else images
    identifier = "sha256:" + "a" * 64

    def run(args, **kwargs):
        calls.append(args)
        if args[3:5] == ["image", "ls"]:
            tag = args[-1].removeprefix("reference=")
            return SimpleNamespace(stdout=images.get(tag, {}).get("Id", ""))
        if args[-1] == "--format={{json .}}":
            return SimpleNamespace(stdout=json.dumps(images[args[5]]))
        if "--network=none" in args:
            tag = args[args.index("-t") + 1]
            assert tag not in images, (
                "Existing diagnostic tags must never be overwritten"
            )
            images[tag] = {
                "Id": identifier,
                "Config": {"Labels": {"devops-quests.lab-asset": "true"}},
            }
        return SimpleNamespace(stdout=identifier + "\n")

    monkeypatch.setattr(module.subprocess, "run", run)
    monkeypatch.setattr(
        module.subprocess, "check_output", lambda args, **kw: run(args).stdout
    )
    return calls


def bootstrap_fixture(root):
    state = root / ".state"
    state.mkdir(parents=True)
    images = {
        key: f"{key}@sha256:fixture"
        for key in (
            "kind",
            "dind",
            "app",
            "gitea",
            "registry",
            "vault",
            "argocd",
            "redis",
            "coredns",
            "traefik",
            "metrics",
            "prometheus",
            "base",
            "docker_cli",
        )
    }
    (root / "images.lock.json").write_text(json.dumps(images))
    for key in (
        "app",
        "argocd",
        "redis",
        "coredns",
        "traefik",
        "metrics",
        "prometheus",
    ):
        (state / f"{key}-oci.tar").write_bytes(b"cached verified fixture")
        (state / f"{key}-oci.ref").write_text(images[key] + " canonical-v2")


def test_bootstrap_builds_and_records_disjoint_tags_for_two_worktrees(
    tmp_path, monkeypatch
):
    monkeypatch.delenv("DQ_IMAGE_NAMESPACE", raising=False)
    monkeypatch.setattr(bootstrap, "TOOLS", {})
    calls = fake_docker(monkeypatch, bootstrap)
    built_tags = []
    for parent in ("one", "two"):
        root = tmp_path / parent / "same-name"
        bootstrap_fixture(root)
        monkeypatch.setattr(bootstrap, "ROOT", root)
        bootstrap.main()
        for filename, name in (
            ("kind-image.json", "kind"),
            ("built-image.json", "workstation"),
        ):
            metadata = json.loads((root / ".state" / filename).read_text())
            tag = image_tag(root, name, "0.1.0")
            assert "tag" not in metadata
            assert metadata["id"] == "sha256:" + "a" * 64
            built_tags.append(tag)
    build_calls = [
        call
        for call in calls
        if call[:4] == ["docker", "--host", "unix:///var/run/docker.sock", "build"]
    ]
    assert [call[call.index("-t") + 1] for call in build_calls] == built_tags
    assert len(set(built_tags)) == 4
    for tag in built_tags:
        assert any(call[3:6] == ["image", "inspect", tag] for call in calls)


def lab_fixture(root):
    source = root / "labs/images/diagnostic"
    source.mkdir(parents=True)
    (source / "main.go").write_text("fixture")
    (source / "Dockerfile").write_text("FROM scratch")
    for filename in ("collections.lock.json", "images.lock.json"):
        (root / "labs" / filename).write_text("{}")
    digest = hashlib.sha256()
    for path in sorted(source.iterdir()):
        digest.update(path.name.encode())
        digest.update(path.read_bytes())
    return "dq-lab-diagnostic:" + digest.hexdigest()[:20]


def test_absent_diagnostic_builds_once_and_is_shared_across_worktrees(
    tmp_path, monkeypatch
):
    calls = fake_docker(monkeypatch, lab_assets)
    monkeypatch.setattr(lab_assets, "IMAGE_LOCK_DIR", tmp_path / "locks")
    for name in ("first", "second"):
        root = tmp_path / name
        tag = lab_fixture(root)
        monkeypatch.setattr(lab_assets, "ROOT", root)
        lab_assets.main()
        assert (root / ".state/lab-images.json").read_text() == json.dumps(
            {"diagnostic": {"tag": tag, "id": "sha256:" + "a" * 64}},
            indent=2,
        ) + "\n"
    builds = [call for call in calls if "--network=none" in call]
    assert len(builds) == 1
    assert builds[0][builds[0].index("-t") + 1] == tag
    assert len([call for call in calls if call[:2] == ["go", "build"]]) == 1


def test_existing_owned_diagnostic_reuses_inspected_id_and_exact_bytes(
    tmp_path, monkeypatch
):
    tag = lab_fixture(tmp_path)
    identifier = "sha256:" + "b" * 64
    calls = fake_docker(
        monkeypatch,
        lab_assets,
        {
            tag: {
                "Id": identifier,
                "Config": {"Labels": {"devops-quests.lab-asset": "true"}},
            },
        },
    )
    monkeypatch.setattr(lab_assets, "ROOT", tmp_path)
    monkeypatch.setattr(lab_assets, "IMAGE_LOCK_DIR", tmp_path / "locks")
    lab_assets.main()
    assert not any("build" in call for call in calls)
    assert (tmp_path / ".state/lab-images.json").read_bytes() == (
        json.dumps({"diagnostic": {"tag": tag, "id": identifier}}, indent=2) + "\n"
    ).encode()


@pytest.mark.parametrize("labels", [None, {}, {"devops-quests.lab-asset": "false"}])
def test_foreign_diagnostic_tag_is_refused_without_build_or_metadata_write(
    tmp_path, monkeypatch, labels
):
    tag = lab_fixture(tmp_path)
    calls = fake_docker(
        monkeypatch,
        lab_assets,
        {tag: {"Id": "sha256:" + "c" * 64, "Config": {"Labels": labels}}},
    )
    monkeypatch.setattr(lab_assets, "ROOT", tmp_path)
    monkeypatch.setattr(lab_assets, "IMAGE_LOCK_DIR", tmp_path / "locks")
    state = tmp_path / ".state"
    state.mkdir()
    metadata = state / "lab-images.json"
    metadata.write_bytes(b"previous metadata")
    with pytest.raises(RuntimeError, match="Refusing to overwrite diagnostic tag"):
        lab_assets.main()
    assert not any("build" in call for call in calls)
    assert metadata.read_bytes() == b"previous metadata"


@pytest.mark.parametrize("with_tags", [False, True])
def test_runtime_reads_immutable_ids_with_old_or_new_metadata(tmp_path, with_tags):
    for name in ("images.lock.json", "levels.yaml"):
        shutil.copyfile(ROOT / name, tmp_path / name)
    state = tmp_path / ".state"
    state.mkdir()
    ids = {}
    for filename, digit in (("built-image.json", "a"), ("kind-image.json", "b")):
        ids[filename] = "sha256:" + digit * 64
        metadata = {"id": ids[filename]}
        if with_tags:
            metadata["tag"] = "devops-quests/unused/tag:0.1.0"
        (state / filename).write_text(json.dumps(metadata))
    runtime = Runtime(state / "runtime", root=tmp_path)
    assert runtime.image == ids["built-image.json"]
    assert runtime.kind_image == ids["kind-image.json"]


def test_tag_only_bootstrap_preserves_metadata_bytes_and_lab_versions(
    tmp_path, monkeypatch
):
    """Use the real LabCatalog digest layout with fixed image identities."""
    root = tmp_path / "checkout"
    bootstrap_fixture(root)
    shutil.copytree(ROOT / "labs", root / "labs")
    shutil.copytree(
        ROOT / "devops_quests",
        root / "devops_quests",
        ignore=shutil.ignore_patterns("__pycache__"),
    )
    (root / "labs/images.lock.json").write_text("{}")
    (root / "labs/collections.lock.json").write_text("{}")
    source = root / "labs/images/diagnostic"
    digest = hashlib.sha256()
    for path in sorted(source.iterdir()):
        digest.update(path.name.encode())
        digest.update(path.read_bytes())
    identifier = "sha256:" + "a" * 64
    # Exact origin/main serialization, including key order and trailing newline.
    expected = {
        "built-image.json": json.dumps({"version": "0.1.0", "id": identifier}) + "\n",
        "kind-image.json": json.dumps(
            {"id": identifier, "upstream": "kind@sha256:fixture"}
        )
        + "\n",
        "lab-images.json": json.dumps(
            {
                "diagnostic": {
                    "tag": "dq-lab-diagnostic:" + digest.hexdigest()[:20],
                    "id": identifier,
                }
            },
            indent=2,
        )
        + "\n",
        "host-images.json": json.dumps({"gitea": identifier}, indent=2) + "\n",
    }
    for name, text in expected.items():
        (root / ".state" / name).write_text(text)
    versions_before = {
        name: profile["version"] for name, profile in LabCatalog(root).profiles.items()
    }
    monkeypatch.setenv("DQ_IMAGE_NAMESPACE", "new-owned-tags")
    monkeypatch.setattr(bootstrap, "ROOT", root)
    monkeypatch.setattr(bootstrap, "TOOLS", {})
    monkeypatch.setattr(lab_assets, "ROOT", root)
    monkeypatch.setattr(lab_assets, "IMAGE_LOCK_DIR", tmp_path / "locks")
    calls = fake_docker(monkeypatch, bootstrap)
    bootstrap.main()
    lab_assets.main()
    for name, text in expected.items():
        assert (root / ".state" / name).read_bytes() == text.encode(), name
    assert {
        name: profile["version"] for name, profile in LabCatalog(root).profiles.items()
    } == versions_before
    built = [call[call.index("-t") + 1] for call in calls if "-t" in call]
    assert len(built) == 3
    assert sum(tag.startswith("devops-quests/new-owned-tags/") for tag in built) == 2
    assert sum(tag.startswith("dq-lab-diagnostic:") for tag in built) == 1
