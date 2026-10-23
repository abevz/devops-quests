import asyncio
import json

import pytest
from aiohttp.test_utils import TestClient, TestServer

from devops_quests.catalog import Catalog
from devops_quests.engine import Engine
from devops_quests.release_info import BuildInfo, UpdateChecker
from devops_quests.server import COOKIE, make_app
from devops_quests.store import Store


async def client_for(tmp_path, checker, status=None):
    manifest = tmp_path / "release"
    manifest.mkdir()
    (manifest / "RELEASE.json").write_text(
        json.dumps({"version": "v1.0.0", "commit": "09d5c7a" + "0" * 33})
    )
    store = Store(tmp_path / "runtime/progress.db")
    store.initialize_admin("admin", "a-long-fixture-password")
    token = store.login("admin", "a-long-fixture-password", "fixture")
    store.add_user("student", "a-long-fixture-password", store.session(token))
    student = store.login("student", "a-long-fixture-password", "fixture")
    if status:
        user = store.session(token)["user_id"]
        run = store.create_run(user, 2, "track", route="Ansible")
        if status == "passed":
            store.finish(run)
        else:
            store.update(run, status=status, ended=store.clock())
    catalog = Catalog()
    engine = Engine(store, catalog, object())
    app = make_app(
        store, catalog, engine, build=BuildInfo.read(manifest), updates=checker
    )
    client = TestClient(TestServer(app))
    await client.start_server()
    return client, token, student


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "status", ["passed", "abandoned", "expired", "setup_failed", "idle"]
)
async def test_finished_attempt_is_persisted_and_has_no_live_topology(tmp_path, status):
    client, token, _ = await client_for(
        tmp_path, UpdateChecker(tmp_path / "cache"), status
    )
    try:
        client.session.cookie_jar.update_cookies({COOKIE: token})
        for _ in range(
            2
        ):  # A fresh state fetch after navigation/reload has the same result.
            state = await (await client.get("/api/state")).json()
            assert state["run"]["status"] == status
            assert state["run"]["level"] == 2
            assert not state["run"]["preparing"]
            assert state["quest"]["id"] == 2
            if status == "passed":
                assert state["run"]["score_details"]["score"] == state["run"]["score"]
            assert await (await client.get("/api/topology")).json() == {"nodes": []}
    finally:
        await client.close()


@pytest.mark.asyncio
async def test_version_is_authenticated_and_notice_is_admin_only(tmp_path):
    async def fetch(_):
        return {"tag_name": "v1.1.0"}

    checker = UpdateChecker(
        tmp_path / "cache", enabled=True, hint="deploy", fetch=fetch
    )
    await checker.check_once()
    client, admin, student = await client_for(tmp_path, checker)
    try:
        assert (await client.get("/api/state")).status == 401
        assert (await client.get("/api/updates")).status == 401
        assert "09d5c7a" not in await (await client.get("/")).text()
        for token in (student, admin):
            client.session.cookie_jar.update_cookies({COOKIE: token})
            state = await (await client.get("/api/state")).json()
            assert state["build"] == {"version": "v1.0.0", "commit": "09d5c7a"}
            update = await client.get("/api/updates")
            if token == student:
                assert update.status == 403
                assert "release_url" not in await update.text()
            else:
                assert (await update.json())["update"]["version"] == "v1.1.0"
    finally:
        await client.close()


@pytest.mark.asyncio
async def test_pending_network_check_does_not_block_app_start(tmp_path):
    started = asyncio.Event()

    async def fetch(_):
        started.set()
        await asyncio.Event().wait()

    checker = UpdateChecker(tmp_path / "cache", enabled=True, fetch=fetch)
    client, admin, _ = await asyncio.wait_for(client_for(tmp_path, checker), timeout=2)
    try:
        await asyncio.wait_for(started.wait(), timeout=1)
        client.session.cookie_jar.update_cookies({COOKIE: admin})
        assert (await client.get("/api/state")).status == 200
        assert await (await client.get("/api/updates")).json() == {"update": None}
    finally:
        await asyncio.wait_for(client.close(), timeout=2)


@pytest.mark.asyncio
async def test_default_app_never_calls_release_fetch(tmp_path, monkeypatch):
    monkeypatch.delenv("DQ_UPDATE_CHECK", raising=False)
    calls = []

    async def fetch(repo):
        calls.append(repo)

    monkeypatch.setattr("devops_quests.release_info.fetch_latest", fetch)
    checker = UpdateChecker.from_environment(tmp_path / "cache")
    client, admin, _ = await client_for(tmp_path, checker)
    try:
        client.session.cookie_jar.update_cookies({COOKIE: admin})
        assert await (await client.get("/api/updates")).json() == {"update": None}
        assert calls == []
    finally:
        await client.close()
