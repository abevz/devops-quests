"""A failed bay cleanup must still stop the exclusive fixture's owned node."""

import conftest
import pytest


def test_failed_teardown_still_stops_owned_node(tmp_path, monkeypatch):
    calls = []

    class FixtureRuntime:
        state = tmp_path
        installation = "0123456789"
        cluster = "devops-quests-0123456789"

        def inspect(self, name):
            return {"Id": "owned-node", "State": {"Running": True}}

        def docker(self, *args, **kwargs):
            calls.append(args)

        def teardown(self, run):
            raise RuntimeError("Synthetic namespace cleanup failed")

    (tmp_path / "kind-owner").write_text(FixtureRuntime.installation)
    (tmp_path / "kind-node-id").write_text("owned-node")
    monkeypatch.setenv("DQ_INTEGRATION", "1")
    monkeypatch.setattr(conftest, "ROOT", tmp_path)
    monkeypatch.setattr(conftest, "Runtime", FixtureRuntime)
    lifecycle = conftest.exclusive_real_sandbox.__wrapped__()
    next(lifecycle)
    with pytest.raises(RuntimeError, match="Synthetic namespace"):
        FixtureRuntime().teardown({})
    with pytest.raises(StopIteration):
        next(lifecycle)
    assert calls == [("stop", "--time", "15", "owned-node")]
