"""Normal polling must collect evidence before checking maintenance objectives."""

import subprocess
from types import SimpleNamespace

import pytest

from devops_quests.catalog import ROOT
from devops_quests.engine import Engine
from devops_quests.store import Store


@pytest.mark.asyncio
@pytest.mark.parametrize("level", [75, 77, 85, 116, 117])
async def test_production_poll_observes_before_objectives(tmp_path, level):
    store = Store(tmp_path / "progress.db")
    token = store.login("admin", store.bootstrap().read_text().strip(), "fixture")
    run = store.create_run(store.session(token)["user_id"], level, "free")
    calls = []

    class Runtime:
        def observe(self, run):
            calls.append("observe")

        def exec(self, run, script, **kwargs):
            assert calls == ["observe"]
            calls.append("check")
            return subprocess.CompletedProcess([], 0, "", "")

    catalog = SimpleNamespace(
        root=ROOT,
        quests={level: {"stages": [{"objectives": [{"check": "true", "keep": True}]}]}},
    )
    result = await Engine(store, catalog, Runtime()).poll(run)
    assert result["goals"] == [True]
    assert calls == ["observe", "check"]
