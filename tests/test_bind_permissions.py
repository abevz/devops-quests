import os
import stat

import pytest

from devops_quests.platform import Platform
from devops_quests.runtime import Runtime


class ExternalBoundaryReached(Exception):
    pass


def stop_before_external_command(*args, **kwargs):
    raise ExternalBoundaryReached


@pytest.mark.parametrize("kind", ["client", "registry"])
def test_bind_credentials_traversable_with_private_service_umask(
    tmp_path, monkeypatch, kind
):
    runtime = Runtime(tmp_path / "private")
    run = {"id": "a" * 24, "level": 1}
    previous = os.umask(0o077)
    try:
        if kind == "client":
            monkeypatch.setattr(runtime, "dependencies", lambda run: set())
            monkeypatch.setattr(runtime, "ensure_network", lambda: None)
            monkeypatch.setattr(runtime, "docker", stop_before_external_command)
            with pytest.raises(ExternalBoundaryReached):
                runtime.create(run)
        else:
            (runtime.state / "bays" / run["id"]).mkdir(mode=0o700, parents=True)
            monkeypatch.setattr(runtime, "command", stop_before_external_command)
            with pytest.raises(ExternalBoundaryReached):
                Platform(runtime).registry(run)
    finally:
        os.umask(previous)
    bay = runtime.state / "bays" / run["id"]
    # The host's private ancestors protect credentials, while a different UID
    # inside the read-only bind mount must be able to traverse its mount root.
    assert stat.S_IMODE(bay.stat().st_mode) == 0o700
    assert stat.S_IMODE((bay / kind).stat().st_mode) == 0o755
    if kind == "client":
        assert stat.S_IMODE((bay / kind / "kubeconfig").stat().st_mode) == 0o644
