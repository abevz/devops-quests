"""Release OCI aliases must resolve by verified content in containerd and CRI."""

import hashlib
import io
import json
import tarfile
from types import SimpleNamespace

import pytest

from devops_quests.runtime import Runtime
from devops_quests.catalog import ROOT


@pytest.fixture
def image_store(tmp_path, monkeypatch):
    config = b'{"architecture":"amd64","os":"linux"}'
    config_id = "sha256:" + hashlib.sha256(config).hexdigest()
    manifest = json.dumps({"config": {"digest": config_id}, "layers": []}).encode()
    manifest_id = "sha256:" + hashlib.sha256(manifest).hexdigest()
    runtime = Runtime.__new__(Runtime)
    runtime.root = tmp_path
    runtime.cluster = "test-kind"
    runtime.images = {"app": "docker.io/library/busybox:1.37.0@" + manifest_id}
    canonical = "docker.io/library/busybox@" + manifest_id
    state = tmp_path / ".state"
    state.mkdir()
    entries, calls = {}, []

    def archive(ref, *, corrupt=False):
        index = {"manifests": [{"digest": manifest_id, "annotations": {}}]}
        if ref is not None:
            index["manifests"][0]["annotations"][
                "org.opencontainers.image.ref.name"
            ] = ref
        members = {
            "index.json": json.dumps(index).encode(),
            "blobs/sha256/" + manifest_id[7:]: manifest + (b" " if corrupt else b""),
            "blobs/sha256/" + config_id[7:]: config,
        }
        with tarfile.open(state / "app-oci.tar", "w") as output:
            for name, raw in members.items():
                item = tarfile.TarInfo(name)
                item.size = len(raw)
                output.addfile(item, io.BytesIO(raw))

    def imported(args, *, stdin, **kwargs):
        calls.append(("import", args))
        with tarfile.open(fileobj=stdin) as source:
            descriptor = json.load(source.extractfile("index.json"))["manifests"][0]
        ref = descriptor["annotations"].get("org.opencontainers.image.ref.name")
        entries[ref or "import-test@" + manifest_id] = descriptor["digest"]
        return SimpleNamespace(returncode=0, stderr=b"")

    def docker(*args, **kwargs):
        calls.append(args)
        if "ls" in args:
            if "-q" in args:
                output = "\n".join(entries)
            else:
                output = "REF TYPE DIGEST SIZE PLATFORMS LABELS\n" + "\n".join(
                    f"{ref} application/vnd.oci.image.manifest.v1+json {digest} 1KiB linux/amd64 -"
                    for ref, digest in entries.items()
                )
            return SimpleNamespace(stdout=output)
        if "tag" in args:
            source, target = args[-2:]
            assert entries[source] == manifest_id
            assert target not in entries
            entries[target] = entries[source]
        elif "rm" in args:
            del entries[args[-1]]
        elif "inspecti" in args:
            return SimpleNamespace(
                returncode=0, stdout=json.dumps({"status": {"id": store.cri_id}})
            )
        return SimpleNamespace(stdout="", returncode=0)

    monkeypatch.setattr("devops_quests.runtime.subprocess.run", imported)
    monkeypatch.setattr(runtime, "docker", docker)
    store = SimpleNamespace(
        runtime=runtime,
        archive=archive,
        entries=entries,
        calls=calls,
        manifest=manifest_id,
        config=config_id,
        canonical=canonical,
        cri_id=config_id,
    )
    return store


@pytest.mark.parametrize(
    "alias",
    [
        "docker.io/library/busybox:1.37.0@{digest}",  # release installer
        "docker.io/library/busybox@{digest}",  # source bootstrap
        "index.docker.io/library/busybox@{digest}",
        "ghcr.io/abevz/devops-quests-app@{digest}",
        "busybox:1.37.0",
        None,  # unnamed OCI layout
    ],
)
def test_import_resolves_manifest_independently_of_oci_annotation(image_store, alias):
    store = image_store
    store.archive(alias.format(digest=store.manifest) if alias else None)
    store.runtime.load_image("app")
    assert store.entries[store.canonical] == store.manifest
    assert any("inspecti" in call for call in store.calls)


@pytest.mark.parametrize(
    "key",
    [
        "app",
        "argocd",
        "redis",
        "coredns",
        "traefik",
        "metrics",
        "prometheus",
        "lab_tools",
        "lab_nginx",
    ],
)
def test_training_bay_and_lab_release_references(image_store, key):
    store = image_store
    references = json.loads((ROOT / "images.lock.json").read_text())
    references.update(json.loads((ROOT / "labs/images.lock.json").read_text()))
    reference = references[key].split("@", 1)[0] + "@" + store.manifest
    store.runtime.images[key] = reference
    store.archive(reference)
    (store.runtime.root / ".state/app-oci.tar").rename(
        store.runtime.root / ".state" / (key + "-oci.tar")
    )
    store.runtime.load_image(key)
    canonical = reference.split("@", 1)[0].rsplit(":", 1)[0] + "@" + store.manifest
    assert store.entries[canonical] == store.manifest
    # A second import must reuse the verified alias without a conflicting tag.
    store.runtime.load_image(key)


def test_digest_in_name_does_not_prove_the_containerd_target(image_store):
    store = image_store
    store.archive("unrelated:latest")
    store.entries[store.canonical] = "sha256:" + "0" * 64
    with pytest.raises(RuntimeError, match="Pinned image"):
        store.runtime.load_image("app")
    assert not any("inspecti" in call for call in store.calls)


def test_unrelated_targets_are_not_tagged_as_the_pinned_manifest(image_store):
    store = image_store
    store.archive("unrelated:latest")

    # Simulate an import which returned success but did not register our manifest.
    def wrong_import(*args, **kwargs):
        store.entries["unrelated:latest"] = "sha256:" + "0" * 64
        return SimpleNamespace(returncode=0, stderr=b"")

    with pytest.MonkeyPatch.context() as patch:
        patch.setattr("devops_quests.runtime.subprocess.run", wrong_import)
        with pytest.raises(RuntimeError, match="Pinned image"):
            store.runtime.load_image("app")
    assert not any("tag" in call for call in store.calls)


def test_corrupt_oci_is_rejected_before_import(image_store):
    store = image_store
    store.archive(store.canonical, corrupt=True)
    with pytest.raises(ValueError, match="content digest mismatch"):
        store.runtime.load_image("app")
    assert not store.calls


def test_cri_must_still_identify_the_verified_content(image_store):
    store = image_store
    store.archive(store.canonical)
    store.cri_id = "sha256:" + "0" * 64
    with pytest.raises(RuntimeError, match="CRI image differs"):
        store.runtime.load_image("app")
