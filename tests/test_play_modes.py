"""Public play-mode authorization, preview side effects and Stop lifecycle."""

import asyncio
from types import SimpleNamespace

import pytest
from aiohttp.test_utils import TestClient, TestServer

from devops_quests.catalog import Catalog
from devops_quests.engine import Engine
from devops_quests.server import COOKIE, make_app
from devops_quests.store import Store


@pytest.fixture
def player(tmp_path):
    store = Store(tmp_path / "profiles/progress.db")
    token = store.login("admin", store.bootstrap().read_text().strip(), "fixture")
    return store, store.session(token), token


class QuietEngine(Engine):
    async def background(self):
        await asyncio.Event().wait()


def fixture_engine(store):
    calls = []
    runtime = SimpleNamespace(
        create=lambda r: calls.append(("create", r["level"])),
        exec=lambda *a, **kw: SimpleNamespace(returncode=0, stdout="", stderr=""),
        teardown=lambda r: calls.append(("teardown", r["level"])),
        capture_facts=lambda *a: None,
    )
    return QuietEngine(store, Catalog(), runtime), calls


async def test_free_records_completion_without_unlocking_campaign_or_tracks(player):
    store, user, _ = player
    uid = user["user_id"]
    engine, calls = fixture_engine(store)
    run = await engine.start(uid, 130, "free")
    assert store.finish(run)["status"] == "passed"
    assert {p["level"] for p in store.progress(uid)} == {130}
    assert store.completions(uid, "campaign") == set()
    assert Catalog().opened(store.completions(uid, "campaign")) == {1}
    Store(
        store.path
    )  # Reopening must never turn later free completions into legacy progress.
    assert store.completions(uid, "campaign") == set()
    with pytest.raises(PermissionError, match="locked"):
        await engine.start(uid, 130, "normal")
    with pytest.raises(PermissionError, match="locked"):
        await engine.start(uid, 130, "track", track="Boss")
    assert calls == [("create", 130)]


async def test_track_has_independent_line_and_campaign_can_qualify_a_track(player):
    store, user, _ = player
    uid = user["user_id"]
    engine, _ = fixture_engine(store)
    run = await engine.start(uid, 2, "track", track="Ansible")
    store.finish(run)
    assert store.completions(uid, "track:Ansible") == {2}
    assert store.completions(uid, "campaign") == set()
    assert engine.catalog.opened({2}, "Ansible") == {2, 5}
    with pytest.raises(PermissionError, match="locked"):
        await engine.start(uid, 3, "track", track="Ansible")
    with pytest.raises(PermissionError, match="locked"):
        await engine.start(uid, 2, "normal")
    run = await engine.start(uid, 1, "normal")
    store.finish(run)
    assert store.completions(uid, "campaign") == {1}
    assert engine.catalog.opened({1}, "Kubernetes") == {1, 4}


async def test_free_still_enforces_global_and_per_user_bay_limits_and_exam_rules(
    player,
):
    store, user, _ = player
    engine, calls = fixture_engine(store)
    uid = user["user_id"]
    store.add_user("other", "other-fixture-password", user)
    other = store.session(store.login("other", "other-fixture-password", "fixture"))[
        "user_id"
    ]
    await engine.start(uid, 99, "free")
    with pytest.raises(ValueError, match="active"):
        await engine.start(uid, 100, "free")
    with pytest.raises(ValueError, match="busy"):
        await engine.start(other, 100, "free")
    with pytest.raises(PermissionError, match="locked"):
        await engine.start(other, 130, "exam")
    with pytest.raises(ValueError):
        await engine.start(other, 1, "invalid")
    assert calls == [("create", 99)]


async def test_authenticated_preview_is_read_only_even_for_locked_levels(player):
    store, user, token = player
    engine, calls = fixture_engine(store)
    client = TestClient(
        TestServer(make_app(store, engine.catalog, engine, base="/devops/"))
    )
    await client.start_server()
    try:
        assert (await client.get("/devops/api/briefing/130")).status == 401
        client.session.cookie_jar.update_cookies({COOKIE: token})
        for _ in range(3):
            response = await client.get("/devops/api/briefing/130")
            assert response.status == 200
            value = await response.json()
            assert value["id"] == 130 and value["stages"] and value["facts"]
            assert value["dependencies"] and len(value["estimated_minutes"]) == 2
            assert value["hints"] == [] and "debrief" not in value
            assert all(
                isinstance(g, dict) and "check" not in g
                for s in value["stages"]
                for g in s["objectives"]
            )
        assert calls == [] and store.run(user=user["user_id"]) is None
        with store.connect() as db:
            assert db.execute("select count(*)from runs").fetchone()[0] == 0
    finally:
        await client.close()


async def test_stop_abandons_without_penalty_releases_capacity_and_is_idempotent(
    player,
):
    store, user, _ = player
    engine, calls = fixture_engine(store)
    run = await engine.start(user["user_id"], 3, "free")
    result = await engine.stop(user["user_id"])
    assert result["status"] == "abandoned" and result["score"] == 0
    assert store.progress(user["user_id"]) == [] and store.active() == []
    again = await engine.stop(user["user_id"])
    assert again["id"] == run["id"]
    assert calls == [("create", 3), ("teardown", 3)]
    await engine.start(user["user_id"], 130, "free")


async def test_stop_during_preparation_waits_then_tears_down(player):
    store, user, _ = player
    engine, calls = fixture_engine(store)
    preparing, release = asyncio.Event(), asyncio.Event()

    async def setup(run):
        preparing.set()
        await release.wait()

    engine.setup_stage = setup
    task = asyncio.create_task(engine.start(user["user_id"], 3, "free"))
    await asyncio.wait_for(preparing.wait(), timeout=5)
    stopping = asyncio.create_task(engine.stop(user["user_id"]))
    await asyncio.sleep(0)
    assert not stopping.done()
    release.set()
    await task
    assert (await stopping)["status"] == "abandoned"
    assert calls == [("create", 3), ("teardown", 3)]


def test_additive_migration_preserves_legacy_progress_and_old_release_passes(player):
    store, user, _ = player
    uid = user["user_id"]
    run = store.create_run(uid, 3, "normal")
    store.finish(run)
    store.set_preferences(uid, "ru", "en")
    before = store.progress(uid)
    with store.connect() as db:
        db.execute("drop table completion_routes")
        db.execute("alter table runs drop column route")
        db.execute("alter table users drop column disabled")
    migrated = Store(store.path)
    assert migrated.progress(uid) == before
    assert migrated.preferences(uid) == {"primary": "ru", "translation": "en"}
    assert migrated.completions(uid, "campaign") == {3}
    assert migrated.session(player[2])
    # Simulate an explicit normal pass recorded by a rolled-back old release.
    later = migrated.create_run(uid, 1, "normal")
    with migrated.connect() as db:
        db.execute("update runs set status='passed' where id=?", (later["id"],))
    assert Store(store.path).completions(uid, "campaign") == {1, 3}


async def test_stop_failure_never_reports_abandoned_or_modifies_previous_results(
    player,
):
    store, user, _ = player
    engine, calls = fixture_engine(store)
    run = await engine.start(user["user_id"], 3, "free")

    def fail(_run):
        raise RuntimeError("synthetic teardown failure")

    engine.runtime.teardown = fail
    with pytest.raises(RuntimeError, match="teardown failure"):
        await engine.stop(user["user_id"])
    assert store.run(run["id"], user["user_id"])["status"] == "active"
    assert store.progress(user["user_id"]) == []
    engine.runtime.teardown = lambda r: calls.append(("teardown", r["level"]))
    assert (await engine.stop(user["user_id"]))["status"] == "abandoned"


async def test_stop_api_needs_origin_csrf_and_cannot_target_another_user(player):
    store, user, _token = player
    engine, calls = fixture_engine(store)
    owner_run = await engine.start(user["user_id"], 3, "free")
    store.add_user("other", "other-fixture-password", user)
    other_token = store.login("other", "other-fixture-password", "fixture")
    other = store.session(other_token)
    client = TestClient(TestServer(make_app(store, engine.catalog, engine)))
    await client.start_server()
    try:
        assert (await client.post("/api/stop", json={})).status == 401
        client.session.cookie_jar.update_cookies({COOKIE: other_token})
        origin = str(client.make_url("/")).rstrip("/")
        assert (
            await client.post("/api/stop", json={}, headers={"Origin": origin})
        ).status == 403
        response = await client.post(
            "/api/stop",
            json={"user_id": user["user_id"], "run_id": owner_run["id"]},
            headers={"Origin": origin, "X-CSRF-Token": other["csrf"]},
        )
        assert response.status == 200 and await response.json() is None
        assert store.run(owner_run["id"], user["user_id"])["status"] == "active"
        assert calls == [("create", 3)]
    finally:
        await client.close()


@pytest.mark.parametrize("minutes", [None, True, "15", [], 1.5, 0, 121])
async def test_invalid_timer_types_never_reach_runtime(player, minutes):
    store, user, _ = player
    engine, calls = fixture_engine(store)
    with pytest.raises(ValueError, match="invalid_exam"):
        await engine.start(user["user_id"], 1, "free", minutes)
    assert calls == [] and store.active() == []
