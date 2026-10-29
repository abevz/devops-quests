"""Free reference reading and one-attempt hint transfers at the public API."""

import asyncio
import json
from types import SimpleNamespace

import pytest
from aiohttp.test_utils import TestClient, TestServer

from devops_quests.catalog import Catalog
from devops_quests.engine import Engine
from devops_quests.scoring import POLICY, breakdown
from devops_quests.server import COOKIE, make_app
from devops_quests.store import Store


class QuietEngine(Engine):
    async def background(self):
        await asyncio.Event().wait()


@pytest.fixture
def profile(tmp_path):
    clock = [10000.0]
    store = Store(tmp_path / "profile/progress.db", clock=lambda: clock[0])
    token = store.login("admin", store.bootstrap().read_text().strip(), "fixture")
    user = store.session(token)["user_id"]
    calls = []
    runtime = SimpleNamespace(
        create=lambda run: calls.append(("create", run["level"])),
        teardown=lambda run: calls.append(("teardown", run["level"])),
        exec=lambda *args, **kwargs: SimpleNamespace(
            returncode=0, stdout="", stderr=""
        ),
        capture_facts=lambda *args: None,
    )
    return store, clock, user, token, QuietEngine(store, Catalog(), runtime), calls


@pytest.mark.parametrize("mode", ["normal", "free"])
async def test_transfer_is_durable_consumed_once_and_scores_like_live_hints(
    profile, mode
):
    store, clock, user, _token, engine, _calls = profile
    with pytest.raises(PermissionError, match="hint_confirm"):
        store.reveal_briefing_hint(user, 1, 3)
    assert store.briefing_hint_count(user, 1) == 0
    assert store.reveal_briefing_hint(user, 1, 3, True) == 1
    assert store.reveal_briefing_hint(user, 1, 3) == 2
    assert Store(store.path).briefing_hint_count(user, 1) == 2
    run = await engine.start(user, 1, mode)
    assert run["hints"] == 2 and store.briefing_hint_count(user, 1) == 0
    clock[0] += 37
    result = store.finish(run)
    assert result["score"] == breakdown(37, 2, 0)["score"]
    assert "No hints" not in json.loads(store.progress(user)[0]["achievements"])
    if mode == "free":
        assert not store.completions(user, "campaign")
    run = await engine.start(user, 1, mode)
    assert run["hints"] == 0
    run = engine.hint(run)
    run = engine.hint(run)
    clock[0] += 37
    assert store.finish(run)["score"] == result["score"]


async def test_reset_keeps_carried_count_and_next_briefing_requires_confirmation(
    profile,
):
    store, clock, user, _token, engine, _calls = profile
    store.reveal_briefing_hint(user, 1, 3, True)
    run = await engine.start(user, 1)
    clock[0] += 1
    reset = await engine.reset(run)
    assert reset["hints"] == 1 and reset["resets"] == 1
    await engine.stop(user)
    with pytest.raises(PermissionError, match="hint_confirm"):
        store.reveal_briefing_hint(user, 1, 3)


async def test_rejected_run_preserves_transfer_and_active_briefing_cannot_bypass_penalty(
    profile,
):
    store, _clock, user, _token, engine, _calls = profile
    store.reveal_briefing_hint(user, 3, 3, True)
    with pytest.raises(PermissionError, match="locked"):
        await engine.start(user, 3)
    assert store.briefing_hint_count(user, 3) == 1
    await engine.start(user, 1)
    with pytest.raises(ValueError, match="active"):
        store.reveal_briefing_hint(user, 1, 3, True)
    assert store.briefing_hint_count(user, 1) == 0


def test_best_record_is_one_whole_attempt_and_debrief_keeps_previous(profile):
    store, clock, user, _token, _engine, _calls = profile
    run = store.create_run(user, 1, "normal")
    store.update(run, hints=1)
    clock[0] += 100
    first = store.finish(store.run(run["id"], user))
    original = store.progress(user)
    run = store.create_run(user, 1, "normal")
    clock[0] += 1000
    worse = store.finish(run)
    assert store.progress(user) == original
    details = store.score_details(worse)
    assert not details["improved"] and details["previous"]["score"] == first["score"]
    run = store.create_run(user, 1, "normal")
    clock[0] += 5
    best = store.finish(run)
    assert store.progress(user)[0]["score"] == best["score"]
    assert store.progress(user)[0]["hints"] == 0
    assert store.progress(user)[0]["seconds"] == 5
    assert store.score_details(best)["improved"]
    assert breakdown(100000, 3, 10)["score"] == POLICY["minimum"]


async def test_api_free_completed_hints_isolation_confirmation_csrf_and_rate_limit(
    profile,
):
    store, _clock, user, token, engine, calls = profile
    client = TestClient(
        TestServer(make_app(store, engine.catalog, engine, base="/devops/"))
    )
    await client.start_server()
    headers = {
        "Cookie": f"{COOKIE}={token}",
        "Origin": str(client.make_url("/")).rstrip("/"),
        "X-CSRF-Token": store.session(token)["csrf"],
    }
    try:
        assert (await client.get("/devops/api/guides")).status == 401
        for path in ["guides", "api/guides", "guide/terraform-4", "api/briefing/1"]:
            assert (await client.get("/devops/" + path, headers=headers)).status == 200
        assert calls == [] and store.run(user=user) is None
        groups = await (await client.get("/devops/api/guides", headers=headers)).json()
        items = [item for group in groups["groups"] for item in group["items"]]
        assert len(items) == len({item["id"] for item in items}) == 33
        assert "kubernetes-workloads" in {item["id"] for item in items}
        assert all(not item["titles"]["en"][0].isdigit() for item in items)
        for alias, canonical in [
            ("kubernetes", "kubernetes-20"),
            ("terraform", "terraform-7.1"),
        ]:
            assert engine.catalog.guide(alias) == engine.catalog.guide(canonical)
        before = await (
            await client.get("/devops/api/briefing/1", headers=headers)
        ).json()
        assert before["hints"] == []
        path = "/devops/api/briefing/1/hint"
        assert (
            await client.post(
                path,
                headers={"Cookie": headers["Cookie"], "Origin": headers["Origin"]},
                json={"confirmed": True},
            )
        ).status == 403
        assert (
            await client.post(
                path,
                headers={**headers, "Origin": "http://evil.invalid"},
                json={"confirmed": True},
            )
        ).status == 403
        assert (await client.post(path, headers=headers, json={})).status == 403
        response = await client.post(
            path, headers=headers, json={"confirmed": True, "count": 3, "user_id": 999}
        )
        assert response.status == 200
        assert len((await response.json())["hints"]) == 1
        store.add_user("other", "synthetic-password-123", store.session(token))
        other = store.login("other", "synthetic-password-123", "fixture-other")
        data = await (
            await client.get(
                "/devops/api/briefing/1", headers={"Cookie": f"{COOKIE}={other}"}
            )
        ).json()
        assert data["hints"] == [] and data["hint_access"]["count"] == 0
        run = await engine.start(user, 1)
        assert run["hints"] == 1
        assert (
            await client.post(path, headers=headers, json={"confirmed": True})
        ).status == 400
        store.finish(run)
        progress, history = store.progress(user), store.run(user=user)
        for _ in range(2):
            data = await (
                await client.get("/devops/api/briefing/1", headers=headers)
            ).json()
            assert len(data["hints"]) == 3 and data["hint_access"]["completed"]
        assert store.progress(user) == progress and store.run(user=user) == history
        assert store.briefing_hint_count(user, 1) == 0
        responses = [
            await client.post(path, headers=headers, json={}) for _ in range(31)
        ]
        assert responses[-1].status == 429
        assert store.briefing_hint_count(user, 1) == 0
    finally:
        await client.close()
