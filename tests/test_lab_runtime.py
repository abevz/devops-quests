"""Ownership and recovery failure paths; never contact the Docker daemon."""

import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from devops_quests.lab_create import create, save_record
from devops_quests.lab_runtime import LabRuntime
from devops_quests.runtime import Runtime


@pytest.fixture
def runtime(tmp_path):
    lab = {"id": "a" * 24, "profile": "helm", "version": "1"}
    runtime = LabRuntime(
        tmp_path,
        Path(__file__).resolve().parents[1],
        lab,
        {"services": ["kubernetes"], "workers": 0},
    )
    return runtime, lab


def node(runtime, identifier="original", networks=None):
    return {
        "Id": identifier,
        "Config": {
            "Image": runtime.kind_image,
            "Labels": {"io.x-k8s.kind.cluster": runtime.cluster},
        },
        "NetworkSettings": {
            "Networks": {runtime.network: {}} if networks is None else networks
        },
        "State": {"Running": False},
    }


def test_replaced_node_is_not_stopped_or_deleted(runtime, monkeypatch):
    runtime, lab = runtime
    runtime.journal.write_text(json.dumps({runtime.node_names()[0]: "original"}))
    replacement = node(runtime, "replacement")
    monkeypatch.setattr(runtime, "inspect", lambda name: replacement)
    commands = []
    monkeypatch.setattr(
        runtime,
        "docker",
        lambda *args, **kwargs: (
            commands.append(args) or SimpleNamespace(stdout="", returncode=0)
        ),
    )
    for action in (runtime.stop, runtime.delete):
        with pytest.raises(RuntimeError, match="node identity"):
            action(lab)
    assert not any(args[0] in {"stop", "rm", "start"} for args in commands)


def test_missing_saved_resource_blocks_resume_without_recreating(runtime, monkeypatch):
    runtime, lab = runtime
    (runtime.state / "ready").write_text(json.dumps({"containers": ["saved-id"]}))
    monkeypatch.setattr(runtime, "containers", list)
    with pytest.raises(RuntimeError, match="missing or replaced"):
        runtime.start(lab)
    assert (runtime.state / "ready").exists()


def test_replacement_with_same_installation_label_is_not_adopted(runtime, monkeypatch):
    runtime, _lab = runtime
    (runtime.state / "ready").write_text(json.dumps({"containers": ["original"]}))
    obj = {
        "Id": "replacement",
        "Config": {"Labels": {"devops-quests.installation": runtime.installation}},
    }
    monkeypatch.setattr(runtime, "inspect", lambda name: obj)
    assert not runtime.owned("same-name")
    obj["Id"] = "original"
    assert runtime.owned("same-name")


def test_interrupted_ip_pin_allows_cleanup_of_exact_disconnected_node(
    runtime, monkeypatch
):
    runtime, _lab = runtime
    runtime.journal.write_text(json.dumps({runtime.node_names()[0]: "original"}))
    obj = node(runtime, networks={})
    monkeypatch.setattr(runtime, "inspect", lambda name: obj)
    assert runtime.nodes() == [obj]
    obj["NetworkSettings"]["Networks"] = {"foreign-network": {}}
    with pytest.raises(RuntimeError, match="node identity"):
        runtime.nodes()


def test_partial_preparation_is_retained_until_explicit_reset(runtime):
    runtime, lab = runtime
    (runtime.state / "started").touch()
    canary = runtime.state / "saved-work"
    canary.write_text("keep")
    with pytest.raises(RuntimeError, match="explicit reset"):
        runtime.start(lab)
    assert canary.read_text() == "keep"


@pytest.mark.parametrize("failed", [False, True])
def test_lab_import_restores_node_cpu_limit(runtime, monkeypatch, failed):
    runtime, _lab = runtime
    name = runtime.node_names()[0]
    obj = {
        "Id": "owned-node",
        "Name": "/" + name,
        "HostConfig": {"NanoCpus": 500_000_000},
    }
    monkeypatch.setattr(runtime, "nodes", lambda: [obj])
    updates = []
    monkeypatch.setattr(runtime, "docker", lambda *args: updates.append(args))

    def unpack(self, key, node=None, timeout=180):
        assert (key, node, timeout) == ("lab_tools", name, 600)
        if failed:
            raise RuntimeError("import interrupted")

    monkeypatch.setattr(Runtime, "load_image", unpack)
    if failed:
        with pytest.raises(RuntimeError, match="import interrupted"):
            runtime.load_image("lab_tools")
    else:
        runtime.load_image("lab_tools")
    assert updates == [
        ("update", "--cpus", "1.0", "owned-node"),
        ("update", "--cpus", "0.5", "owned-node"),
    ]


def test_ansible_bay_teardown_does_not_stop_a_foreign_game_node(tmp_path, monkeypatch):
    runtime = Runtime(tmp_path)
    foreign = {
        "State": {"Running": True},
        "Config": {"Image": "foreign"},
        "NetworkSettings": {"Networks": {"foreign": {}}},
    }
    monkeypatch.setattr(
        runtime,
        "inspect",
        lambda name: foreign if name == runtime.cluster + "-control-plane" else None,
    )
    commands = []

    def docker(*args, **kwargs):
        commands.append(args)
        return SimpleNamespace(stdout="", returncode=1 if "inspect" in args else 0)

    monkeypatch.setattr(runtime, "docker", docker)
    runtime.teardown({"id": "b" * 24, "level": 2})
    assert not any(args[0] == "stop" for args in commands)


def pending_creation(runtime, monkeypatch):
    runtime.creation.write_text(
        json.dumps(
            {
                "status": "pending",
                "token": "attempt-1",
                "network_id": "private-network-id",
                "started": "2026-01-01T00:00:00+00:00",
            }
        )
    )
    obj = node(runtime, networks={runtime.network: {"NetworkID": "private-network-id"}})
    obj["Created"] = "2026-01-01T00:00:01Z"
    monkeypatch.setattr(runtime, "inspect", lambda name: obj)
    network = {
        "Id": "private-network-id",
        "Labels": {"devops-quests.installation": runtime.installation},
    }
    monkeypatch.setattr(
        runtime,
        "docker",
        lambda *args, **kwargs: SimpleNamespace(
            stdout=json.dumps([network]), returncode=0
        ),
    )
    return obj


def test_recovery_journals_private_partial_creation_and_cancels_delayed_worker(
    runtime, monkeypatch
):
    runtime, _lab = runtime
    obj = pending_creation(runtime, monkeypatch)
    runtime.settle_creation()
    assert json.loads(runtime.journal.read_text()) == {
        runtime.node_names()[0]: obj["Id"]
    }
    assert runtime.nodes() == [obj]
    # Recovery won the lock before the child started: no command is executed.
    create(runtime.creation, "attempt-1")
    assert json.loads(runtime.creation.read_text())["status"] == "settled"
    # A subsequent replacement still cannot be adopted, even with the same labels.
    obj["Id"] = "replacement"
    runtime.settle_creation()
    with pytest.raises(RuntimeError, match="node identity"):
        runtime.nodes()


@pytest.mark.parametrize("changed", ["network", "image", "created"])
def test_partial_creation_refuses_unverified_nodes(runtime, monkeypatch, changed):
    runtime, _lab = runtime
    obj = pending_creation(runtime, monkeypatch)
    if changed == "network":
        obj["NetworkSettings"]["Networks"][runtime.network]["NetworkID"] = "foreign-id"
    elif changed == "image":
        obj["Config"]["Image"] = "foreign-image"
    else:
        obj["Created"] = "2025-12-31T23:59:59Z"
    with pytest.raises(RuntimeError, match="partially created"):
        runtime.settle_creation()
    assert not runtime.journal.exists()


def test_delayed_worker_from_before_reset_cannot_launch_a_new_attempt(
    runtime, monkeypatch
):
    runtime, _lab = runtime
    pending_creation(runtime, monkeypatch)
    create(runtime.creation, "old-attempt")
    assert json.loads(runtime.creation.read_text())["status"] == "pending"


@pytest.mark.parametrize("identity", [None, "original", "replacement"])
def test_bay_teardown_stops_only_the_recorded_kind_id(tmp_path, monkeypatch, identity):
    runtime = Runtime(tmp_path)
    (tmp_path / "kind-owner").write_text(runtime.installation)
    if identity:
        (tmp_path / "kind-node-id").write_text(identity)
    obj = {
        "Id": "original",
        "State": {"Running": True},
        "Config": {
            "Image": runtime.kind_image,
            "Labels": {"io.x-k8s.kind.cluster": runtime.cluster},
        },
        "NetworkSettings": {"Networks": {runtime.network: {}}},
    }
    monkeypatch.setattr(
        runtime,
        "inspect",
        lambda name: obj if name == runtime.cluster + "-control-plane" else None,
    )
    commands = []

    def docker(*args, **kwargs):
        commands.append(args)
        return SimpleNamespace(stdout="", returncode=1 if "inspect" in args else 0)

    monkeypatch.setattr(runtime, "docker", docker)
    runtime.teardown({"id": "b" * 24, "level": 2})
    assert any(args[0] == "stop" for args in commands) == (identity == "original")


def test_interrupted_delete_does_not_reopen_finished_creation(runtime, monkeypatch):
    runtime, lab = runtime
    runtime.creation.write_text(json.dumps({"status": "settled"}))
    runtime.journal.write_text("{}")
    monkeypatch.setattr(runtime, "containers", lambda **kwargs: [])
    monkeypatch.setattr(runtime, "firewall", lambda **kwargs: None)

    def docker(*args, **kwargs):
        if args[:2] == ("network", "inspect"):
            return SimpleNamespace(
                returncode=0,
                stdout=json.dumps(
                    [{"Labels": {"devops-quests.installation": runtime.installation}}]
                ),
            )
        if args[:2] == ("network", "rm"):
            raise RuntimeError("simulated crash after network removal")
        return SimpleNamespace(returncode=0, stdout="")

    monkeypatch.setattr(runtime, "docker", docker)
    with pytest.raises(RuntimeError, match="simulated crash"):
        runtime.delete(lab)
    assert not runtime.creation.exists()
    # A later recovery must not inspect the already removed creation network.
    monkeypatch.setattr(
        runtime,
        "docker",
        lambda *args, **kwargs: pytest.fail("unexpected Docker access"),
    )
    runtime.stop(lab)


def test_interrupted_record_write_leaves_previous_identity_valid(tmp_path, monkeypatch):
    path = tmp_path / "ready"
    save_record(path, {"containers": ["original"]})

    def interrupted(*args, **kwargs):
        raise OSError("crash before publication")

    monkeypatch.setattr(Path, "replace", interrupted)
    with pytest.raises(OSError, match="before publication"):
        save_record(path, {"containers": ["new"]})
    assert json.loads(path.read_text()) == {"containers": ["original"]}
