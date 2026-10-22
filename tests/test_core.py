import pytest
import yaml
from aiohttp.test_utils import TestClient, TestServer

from devops_quests.catalog import RELEASED, ROOT, Catalog
from devops_quests.engine import Engine
from devops_quests.server import make_app
from devops_quests.store import ABSOLUTE, IDLE, Store


def test_curriculum_additions():
    rows = yaml.safe_load((ROOT / "levels.yaml").read_text())
    assert [r["id"] for r in rows] == list(range(1, len(rows) + 1))
    assert len(rows) >= 100
    catalog = Catalog()
    assert all(
        catalog.level_messages["ru"][row["skill"]]
        and catalog.level_messages["ru"][row["story"]]
        for row in rows
    )
    release = [r for r in rows if r["release"] == 1]
    assert {r["id"] for r in release} <= set(RELEASED)
    for difficulty in ("basics", "medium", "complex", "expert"):
        group = [r for r in release if r["difficulty"] == difficulty]
        assert len(group) == 10
        assert any(
            "module" in catalog.level_messages["en"][r["skill"]].lower() for r in group
        )
    platform = [
        r
        for r in release
        if set(r["dependencies"]) & {"gitea", "argocd", "registry", "vault"}
    ]
    assert [r["id"] for r in platform] == [27, 54, 83]
    assert set(rows[99]["dependencies"]) == {
        "gitea",
        "registry",
        "argocd",
        "vault",
        "kubernetes",
    }
    assert all(
        "moved" in catalog.level_messages["en"][r["skill"]]
        for r in release
        if r["id"] == 84
    )


@pytest.fixture
def profile(tmp_path):
    clock = [10000.0]
    store = Store(tmp_path / "private/progress.db", clock=lambda: clock[0])
    path = store.bootstrap()
    token = store.login("admin", path.read_text().strip(), "local")
    return store, clock, token


def test_profile_password_sessions_limits(profile):
    s, c, token = profile
    user = s.session(token)
    assert user["admin"] and user["name"] == "admin"
    with s.connect() as db:
        row = db.execute("SELECT password FROM users").fetchone()
        assert row[0].startswith("pbkdf2-sha256$") and token not in str(
            db.execute("SELECT * FROM sessions").fetchall()
        )
    c[0] += IDLE
    assert s.session(token) is None
    for _ in range(8):
        assert s.login("admin", "wrong", "other") is None
    with pytest.raises(PermissionError):
        s.login("admin", "wrong", "other")
    c[0] += 901
    assert s.login("admin", "wrong", "other") is None
    s.add_user("student", "a-long-test-password", user)
    with pytest.raises(PermissionError):
        s.add_user("intruder", "a-long-test-password", {"admin": 0})


def test_normal_and_exam_separate_scoring_backup(profile, tmp_path):
    s, c, t = profile
    u = s.session(t)["user_id"]
    run = s.create_run(u, 1, "normal")
    c[0] += 100
    s.update(run, hints=1, resets=1)
    run = s.run(run["id"], u)
    passed = s.finish(run)
    assert passed["score"] == 780 and len(s.progress(u)) == 1
    run = s.create_run(u, 1, "exam", 1)
    c[0] += 61
    assert s.finish(run)["status"] == "expired"
    assert s.progress(u)[0]["score"] == 780 and len(s.exams(u)) == 1
    target = tmp_path / "backup/progress.db"
    s.backup(target)
    assert target.stat().st_mode & 0o777 == 0o600


@pytest.mark.asyncio
async def test_background_http_poll_does_not_extend_idle_session(profile):
    store, clock, token = profile
    catalog = Catalog()
    engine = Engine(store, catalog, object())
    client = TestClient(TestServer(make_app(store, catalog, engine)))
    await client.start_server()
    client.session.cookie_jar.update_cookies({"devops_quests_session": token})
    try:
        clock[0] += IDLE - 1
        assert (await client.get("/api/state")).status == 200
        clock[0] += 1
        assert (await client.get("/api/state")).status == 401
        token = store.login(
            "admin", (store.path.parent / "admin-password").read_text().strip(), "local"
        )
        for _ in range(ABSOLUTE // 3600 - 1):
            clock[0] += 3600
            assert store.session(token, touch=True)
        clock[0] += 3600
        assert store.session(token, touch=True) is None
    finally:
        await client.close()


@pytest.mark.asyncio
async def test_auth_csrf_basepath_ws_and_no_reference_exposure(profile):
    s, _c, t = profile
    cat = Catalog()

    class Runtime:
        def names(self, r):
            return {"workstation": "never-opened"}

        def owned(self, n):
            raise AssertionError("Unauthenticated request reached runtime")

    engine = Engine(s, cat, Runtime())
    client = TestClient(TestServer(make_app(s, cat, engine, base="/devops/")))
    await client.start_server()
    try:
        origin = str(client.make_url("")).rstrip("/")
        response = await client.get("/devops/api/state")
        assert response.status == 401
        with pytest.raises(Exception) as error:
            await client.ws_connect("/devops/api/terminal", headers={"Origin": origin})
        assert getattr(error.value, "status", None) == 401
        response = await client.post(
            "/devops/api/login",
            json={"name": "admin", "password": "wrong"},
            headers={"Origin": "http://evil.test"},
        )
        assert response.status == 403
        response = await client.get("/devops/assets/../solutions/001/reference.sh")
        assert response.status in (401, 404)
        client.session.cookie_jar.update_cookies({"devops_quests_session": t})
        response = await client.get("/devops/api/state")
        assert response.status == 200
        data = await response.json()
        assert data["user"]["name"] == "admin"
        response = await client.get("/devops/api/topology")
        assert response.status == 200 and await response.json() == {"nodes": []}
        response = await client.post(
            "/devops/api/start", json={"level": 1}, headers={"Origin": origin}
        )
        assert response.status == 403
        with pytest.raises(Exception) as error:
            await client.ws_connect(
                "/devops/api/terminal", headers={"Origin": "http://evil.test"}
            )
        assert getattr(error.value, "status", None) == 403
        response = await client.get("/devops/assets/solutions/001/reference.sh")
        assert response.status == 404
    finally:
        await client.close()


def test_all_quests_assets_bilingual_and_no_check_leaks():
    cat = Catalog()
    assert set(cat.quests) == set(RELEASED)
    assert cat.opened(set()) == {1}
    next_level = next(number for number in cat.released if number not in range(1, 11))
    assert cat.opened(set(range(1, 11))) == set(range(1, 11)) | {next_level}
    for number in RELEASED:
        q = cat.quests[number]
        assert len(q["hints"]) == 3 and len(q["phrases"]) >= 3
        completed = cat.public(number, hints=0, debrief=True)
        assert completed["hints"] == [] and completed["guides"]
        assert "guides" not in cat.public(number)
        import json

        guides = json.loads((ROOT / "docs/guide-excerpts.json").read_text())
        assert all(
            (
                h.get("guide") in guides
                or h.get("url", "").startswith("https://developer.hashicorp.com/vault/")
            )
            for h in q["hints"]
        )
        for data in (q["title"], q["brief"], q["debrief"], *q["phrases"]):
            assert cat.text(number, data)["en"] and cat.text(number, data)["ru"]
        for i, stage in enumerate(q["stages"]):
            assert (
                cat.text(number, stage["brief"])["en"]
                and cat.text(number, stage["brief"])["ru"]
                and stage["objectives"]
            )
            for goal in stage["objectives"]:
                assert cat.text(number, goal["text"])["ru"] and goal["check"]
            # Later stages may continue the same live incident without mutation.
            assert (ROOT / "quests" / f"{number:03}" / f"setup-{i}.sh").is_file()
            if i == 0:
                assert cat.script(number, i, "setup").strip() != "true"
            assert (ROOT / "solutions" / f"{number:03}" / f"{i}.sh").is_file()
        public = cat.public(number, 3, False, True)
        assert not public["hints"] and "debrief" not in public
        assert all(
            "check" not in goal
            for stage in public["stages"]
            for goal in stage["objectives"]
        )


@pytest.mark.asyncio
async def test_engine_stage_reset_exam_and_real_failure_semantics(profile):
    import subprocess

    s, c, t = profile
    u = s.session(t)["user_id"]
    cat = Catalog()
    calls = []

    class Runtime:
        solved = False

        def create(self, r):
            calls.append(("create", r["id"]))

        def teardown(self, r):
            calls.append(("teardown", r["id"]))

        def exec(self, r, script, **kwargs):
            if "check=False" in script:
                raise AssertionError()
            return subprocess.CompletedProcess([], 0 if self.solved else 1, "", "")

    runtime = Runtime()
    engine = Engine(s, cat, runtime)
    run = await engine.start(u, 1)
    with pytest.raises(ValueError):
        await engine.start(u, 1)
    run = engine.hint(run)
    assert run["hints"] == 1
    run = await engine.poll(run, True)
    assert run["status"] == "active" and run["goals"] == [False]
    run = await engine.reset(run)
    assert run["resets"] == 1 and run["hints"] == 1
    runtime.solved = True
    run = await engine.poll(run, True)
    assert run["status"] == "passed"
    assert s.progress(u)[0]["score"] <= 800
    run = await engine.start(u, 1, "exam", 1)
    with pytest.raises(PermissionError):
        engine.hint(run)
    c[0] += 61
    assert (await engine.poll(run, True))["status"] == "expired"
    assert len(s.progress(u)) == 1


@pytest.mark.asyncio
async def test_preparation_cannot_complete_goals_or_burn_exam_time(profile):
    import asyncio
    import subprocess
    import threading

    s, clock, token = profile
    u = s.session(token)["user_id"]
    prior = s.create_run(u, 1, "normal")
    s.finish(prior)
    gate = threading.Event()
    entered = threading.Event()
    calls = []

    class Runtime:
        def create(self, r):
            entered.set()
            assert gate.wait(5)

        def teardown(self, r):
            pass

        def exec(self, r, script, **kw):
            calls.append(script)
            return subprocess.CompletedProcess([], 0, "", "")

    engine = Engine(s, Catalog(), Runtime())
    starting = asyncio.create_task(engine.start(u, 1, "exam", 15))
    try:
        for _ in range(50):
            if entered.is_set():
                break
            await asyncio.sleep(0.01)
        assert entered.is_set()
        pending = s.active()[0]
        clock[0] += 300
        assert (await engine.poll(pending, True))["status"] == "active"
        assert calls == [] and len(s.progress(u)) == 1
        gate.set()
        run = await starting
        assert run["started"] == clock[0] and run["deadline"] - clock[0] == 900
        assert len(calls) == 1
    finally:
        gate.set()
        if not starting.done():
            await starting


@pytest.mark.asyncio
async def test_explicit_https_proxy_origin_sets_secure_cookie_and_rejects_http(profile):
    store, _clock, _token = profile
    catalog = Catalog()
    engine = Engine(store, catalog, object())
    client = TestClient(
        TestServer(
            make_app(
                store,
                catalog,
                engine,
                "/devops/",
                {"training.example.test"},
                "https://training.example.test",
            )
        )
    )
    await client.start_server()
    try:
        payload = {
            "name": "admin",
            "password": (store.path.parent / "admin-password").read_text().strip(),
        }
        response = await client.post(
            "/devops/api/login",
            json=payload,
            headers={"Host": "training.example.test", "Origin": "https://training.example.test"},
        )
        assert response.status == 200
        assert response.cookies["devops_quests_session"]["secure"]
        assert response.cookies["devops_quests_session"]["path"] == "/devops/"
        response = await client.post(
            "/devops/api/login",
            json=payload,
            headers={"Host": "training.example.test", "Origin": "http://training.example.test"},
        )
        assert response.status == 403
        # Arbitrary forwarded headers never replace the explicitly configured origin.
        response = await client.post(
            "/devops/api/login",
            json=payload,
            headers={
                "Host": "training.example.test",
                "Origin": "https://evil.invalid",
                "X-Forwarded-Proto": "https",
            },
        )
        assert response.status == 403
    finally:
        await client.close()
