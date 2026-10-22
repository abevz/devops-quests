"""Real sandbox checks must not compete with an interactive app instance."""

import fcntl
import os

import pytest

from devops_quests.catalog import ROOT
from devops_quests.runtime import Runtime


@pytest.fixture(scope="session", autouse=True)
def exclusive_real_sandbox():
    if os.environ.get("DQ_INTEGRATION") != "1":
        yield
        return
    path = ROOT / ".state/runtime/server.lock"
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with path.open("a") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pytest.fail("Stop this installation app before real sandbox tests.")
        previous_umask = os.umask(0o077)
        # Keep only the shared, installation-owned node warm during this
        # exclusive matrix. Every bay still follows production teardown.
        patch = pytest.MonkeyPatch()
        docker = Runtime.docker
        teardown = Runtime.teardown
        warmed = set()

        def matrix_docker(runtime, *args, **kwargs):
            if getattr(runtime, "_matrix_teardown", False) and args[:3] == (
                "stop",
                "--time",
                "15",
            ):
                node = runtime.inspect(runtime.cluster + "-control-plane")
                if node and args[3:] == (node["Id"],):
                    warmed.add(runtime)
                    return None
            return docker(runtime, *args, **kwargs)

        def matrix_teardown(runtime, run):
            warmed.add(runtime)
            runtime._matrix_teardown = True
            try:
                return teardown(runtime, run)
            finally:
                runtime._matrix_teardown = False

        patch.setattr(Runtime, "docker", matrix_docker)
        patch.setattr(Runtime, "teardown", matrix_teardown)
        try:
            yield
        finally:
            patch.undo()
            try:
                for runtime in warmed:
                    node = runtime.inspect(runtime.cluster + "-control-plane")
                    marker = runtime.state / "kind-owner"
                    if node and node["State"]["Running"]:
                        assert marker.read_text().strip() == runtime.installation
                        assert (runtime.state / "kind-node-id").read_text() == node[
                            "Id"
                        ]
                        runtime.docker(
                            "stop",
                            "--time",
                            "15",
                            node["Id"],
                            timeout=60,
                        )
            finally:
                os.umask(previous_umask)
