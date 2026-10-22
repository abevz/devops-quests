import asyncio
from pathlib import Path
from types import SimpleNamespace

import pytest
from aiohttp.test_utils import TestClient, TestServer

from devops_quests.catalog import Catalog
from devops_quests.engine import Engine
from devops_quests.labs import LabCatalog, LabManager, LabTerminalStore
from devops_quests.server import COOKIE, make_app
from devops_quests.store import Store


@pytest.fixture
def context(tmp_path):
    store = Store(tmp_path / "profile.db")
    token = store.login("admin", store.bootstrap().read_text().strip(), "test")
    owner = store.session(token)
    store.add_user("other", "a second long password", owner)
    runtime = SimpleNamespace(create=lambda run: None, teardown=lambda run: None)
    engine = Engine(store, Catalog(), runtime)
    calls, work = [], {}

    class FakeLab:
        def start(self, lab):
            work.setdefault(lab["id"], {"files": "saved", "running": False})[
                "running"
            ] = True
            calls.append("start")

        def stop(self, lab):
            if lab["id"] in work:
                work[lab["id"]]["running"] = False
            calls.append("stop")

        def delete(self, lab):
            work.pop(lab["id"], None)
            calls.append("delete")

    manager = LabManager(
        store,
        engine,
        LabCatalog(Path(__file__).resolve().parents[1]),
        lambda lab: FakeLab(),
    )
    return store, owner["user_id"], manager, work, calls


async def settled(manager):
    await asyncio.gather(*tuple(manager.tasks.values()))


async def test_slot_blocks_both_directions_without_changing_attempts(context):
    store, user, manager, work, _calls = context
    first = await manager.create(user, "ansible")
    with pytest.raises(ValueError, match="lab_busy"):
        await manager.engine.start(user, 1, "free")
    await settled(manager)
    assert not store.active() and not store.progress(user)
    await manager.action(user, first["id"], "stop")
    await settled(manager)
    run = store.create_run(user, 1, "free")
    with pytest.raises(ValueError, match="lab_busy"):
        await manager.action(user, first["id"], "start")
    assert store.run(run["id"], user)["status"] == "active"
    assert work[first["id"]]["files"] == "saved"


async def test_saved_work_survives_restart_but_not_explicit_reset(context):
    store, user, manager, work, calls = context
    lab = await manager.create(user, "ansible")
    await settled(manager)
    work[lab["id"]]["files"] = "owner edit"
    manager.store = Store(store.path)
    await manager.recover()
    assert store.lab(lab["id"], user)["status"] == "stopped"
    assert not work[lab["id"]]["running"]
    await manager.action(user, lab["id"], "start")
    await settled(manager)
    assert work[lab["id"]]["files"] == "owner edit"
    with pytest.raises(ValueError, match="lab_confirm"):
        await manager.action(user, lab["id"], "reset")
    await manager.action(user, lab["id"], "reset", lab["id"])
    await settled(manager)
    assert work[lab["id"]]["files"] == "saved"
    assert calls.count("delete") == 1


async def test_owner_isolation_and_terminal_status(context):
    store, user, manager, _work, _calls = context
    lab = await manager.create(user, "helm")
    await settled(manager)
    with pytest.raises(ValueError, match="lab_missing"):
        await manager.action(2, lab["id"], "delete", lab["id"])
    assert not store.lab(lab["id"], 2)
    assert LabTerminalStore(store).run(lab["id"], user)["status"] == "active"
    await manager.action(user, lab["id"], "stop")
    await settled(manager)
    assert LabTerminalStore(store).run(lab["id"], user)["status"] == "stopped"


async def test_failed_stop_retains_slot_and_data_until_recovery(context):
    store, user, manager, work, _calls = context
    lab = await manager.create(user, "ansible")
    await settled(manager)
    factory = manager.factory

    def fail(*args):
        raise RuntimeError("daemon unavailable")

    manager.factory = lambda lab: SimpleNamespace(stop=fail)
    await manager.action(user, lab["id"], "stop")
    await settled(manager)
    failed = store.lab(lab["id"], user)
    assert failed["slot"] == 1 and failed["status"] == "error"
    with pytest.raises(ValueError, match="lab_busy"):
        store.create_run(user, 1, "normal")
    assert work[lab["id"]]["files"] == "saved"
    manager.factory = factory
    await manager.recover()
    assert not store.lab(lab["id"], user)["slot"]


async def test_two_users_cannot_prepare_concurrently_and_versions_do_not_upgrade_silently(
    context,
):
    store, user, manager, work, _calls = context
    results = await asyncio.gather(
        manager.create(user, "helm"),
        manager.create(2, "ansible"),
        return_exceptions=True,
    )
    assert sum(isinstance(result, ValueError) for result in results) == 1
    await settled(manager)
    await manager.recover()
    lab = store.labs(user)[0]
    manager.catalog.profiles[lab["profile"]]["version"] = "2"
    with pytest.raises(ValueError, match="lab_version"):
        await manager.action(user, lab["id"], "start")
    assert work[lab["id"]]["files"] == "saved"


async def test_lab_api_auth_csrf_owner_and_explicit_deletion(context):
    store, user, manager, work, _calls = context
    owner_token = store.login(
        "admin", (store.path.parent / "admin-password").read_text().strip(), "api-test"
    )
    other_token = store.login("other", "a second long password", "api-test")
    client = TestClient(
        TestServer(
            make_app(store, manager.engine.catalog, manager.engine, labs=manager)
        )
    )
    await client.start_server()
    origin = str(client.make_url("/")).rstrip("/")

    def headers(token):
        return {
            "Origin": origin,
            "Cookie": f"{COOKIE}={token}",
            "X-CSRF-Token": store.session(token)["csrf"],
        }

    try:
        assert (await client.get("/api/labs")).status == 401
        missing_csrf = headers(owner_token)
        missing_csrf.pop("X-CSRF-Token")
        assert (
            await client.post(
                "/api/labs", json={"profile": "ansible"}, headers=missing_csrf
            )
        ).status == 403
        assert (
            await client.post("/api/labs", json=[], headers=headers(owner_token))
        ).status == 400
        response = await client.post(
            "/api/labs", json={"profile": "ansible"}, headers=headers(owner_token)
        )
        assert response.status == 200
        lab = await response.json()
        await settled(manager)
        path = "/api/labs/" + lab["id"]
        other = await client.get("/api/labs", headers=headers(other_token))
        assert (await other.json())["saved"] == []
        for action in ("stop", "reset", "delete"):
            response = await client.post(
                path,
                json={"action": action, "confirmation": lab["id"]},
                headers=headers(other_token),
            )
            assert response.status == 400
        assert (
            await client.get(path + "/terminal", headers=headers(other_token))
        ).status == 400
        assert (
            await client.get(
                path + "/terminal",
                headers={**headers(owner_token), "Origin": "https://foreign.invalid"},
            )
        ).status == 403
        assert (
            await client.post(
                path, json={"action": "delete"}, headers=headers(owner_token)
            )
        ).status == 400
        await client.post(path, json={"action": "stop"}, headers=headers(owner_token))
        await settled(manager)
        assert (
            await client.get(path + "/terminal", headers=headers(owner_token))
        ).status == 400
        await client.post(
            path,
            json={"action": "delete", "confirmation": lab["id"]},
            headers=headers(owner_token),
        )
        await settled(manager)
        assert not store.labs(user) and lab["id"] not in work
        assert not store.progress(user) and not store.active()
    finally:
        await client.close()
