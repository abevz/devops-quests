"""Profile/account operations preserve progress and enforce actor/session boundaries."""

import asyncio

import pytest
from aiohttp.test_utils import TestClient, TestServer

from devops_quests.catalog import Catalog
from devops_quests.engine import Engine
from devops_quests.server import COOKIE, make_app
from devops_quests.store import Store, password_matches

PASSWORD = "initial-fixture-password"
NEW = "replacement-fixture-password"


@pytest.fixture
def accounts(tmp_path):
    store = Store(tmp_path / "private/progress.db")
    initial = store.bootstrap().read_text().strip()
    token = store.login("admin", initial, "fixture")
    admin = store.session(token)
    store.add_user("student", PASSWORD, admin)
    student_token = store.login("student", PASSWORD, "fixture")
    return store, admin, token, store.session(student_token), student_token, initial


def test_own_password_current_confirmation_hash_and_other_sessions(accounts):
    store, _, _, student, token, _ = accounts
    other = store.login("student", PASSWORD, "fixture")
    for current, new, repeat in (
        ("wrong", NEW, NEW),
        (PASSWORD, NEW, "different"),
        (PASSWORD, "short", "short"),
    ):
        with pytest.raises(ValueError):
            store.change_password(student, token, current, new, repeat)
    store.change_password(student, token, PASSWORD, NEW, NEW)
    assert store.session(token) and store.session(other) is None
    assert store.login("student", PASSWORD, "fixture") is None
    assert store.login("student", NEW, "fixture")
    with store.connect() as db:
        encoded = db.execute(
            "select password from users where id=?", (student["user_id"],)
        ).fetchone()[0]
    assert encoded != NEW and password_matches(NEW, encoded)


def test_password_attempt_limit_is_persistent(accounts):
    store, _, _, student, token, _ = accounts
    for _ in range(8):
        with pytest.raises(ValueError, match="current_password"):
            store.change_password(student, token, "wrong", NEW, NEW)
    with pytest.raises(PermissionError, match="attempts"):
        Store(store.path).change_password(student, token, PASSWORD, NEW, NEW)
    assert store.session(token)


def test_admin_reset_disable_last_admin_and_preserve_progress(accounts):
    store, admin, _, student, token, _ = accounts
    uid = student["user_id"]
    run = store.create_run(uid, 3, "free")
    store.finish(run)
    before = store.progress(uid)
    for operation in (
        lambda: store.users(student),
        lambda: store.reset_password(student, admin["user_id"], NEW),
        lambda: store.set_enabled(student, admin["user_id"], False),
    ):
        with pytest.raises(PermissionError):
            operation()
    store.reset_password(admin, uid, NEW)
    assert store.session(token) is None
    token = store.login("student", NEW, "fixture")
    store.set_enabled(admin, uid, False)
    assert (
        store.session(token) is None and store.login("student", NEW, "fixture") is None
    )
    with pytest.raises(PermissionError):
        store.create_run(uid, 1, "free")
    store.set_enabled(admin, uid, True)
    assert store.login("student", NEW, "fixture") and store.progress(uid) == before
    with pytest.raises(ValueError, match="last_admin"):
        store.set_enabled(admin, admin["user_id"], False)
    rows = store.users(admin)
    assert rows and all(set(r) == {"id", "name", "admin", "enabled"} for r in rows)


async def test_account_api_authorization_origin_csrf_and_target_ownership(accounts):
    store, admin, token, student, student_token, initial = accounts

    class Quiet(Engine):
        async def background(self):
            await asyncio.Event().wait()

    catalog = Catalog()
    client = TestClient(
        TestServer(
            make_app(store, catalog, Quiet(store, catalog, object()), base="/devops/")
        )
    )
    await client.start_server()
    try:
        assert (await client.get("/devops/api/users")).status == 401
        client.session.cookie_jar.update_cookies({COOKIE: student_token})
        origin = str(client.make_url("/")).rstrip("/")
        headers = {"Origin": origin, "X-CSRF-Token": student["csrf"]}
        assert (await client.get("/devops/api/users")).status == 403
        for path, data in (
            (
                "password",
                {
                    "current": PASSWORD,
                    "password": NEW,
                    "confirmation": NEW,
                    "user_id": admin["user_id"],
                },
            ),
            ("users/reset", {"user_id": admin["user_id"], "password": NEW}),
            ("users/enabled", {"user_id": admin["user_id"], "enabled": False}),
        ):
            assert (
                await client.post(
                    "/devops/api/" + path, json=data, headers={"Origin": origin}
                )
            ).status == 403
            assert (
                await client.post(
                    "/devops/api/" + path,
                    json=data,
                    headers={**headers, "Origin": "http://evil.invalid"},
                )
            ).status == 403
            assert (
                await client.post("/devops/api/" + path, json=data, headers=headers)
            ).status == 403
        assert store.login("admin", initial, "fixture")
        client.session.cookie_jar.update_cookies({COOKIE: token})
        headers = {"Origin": origin, "X-CSRF-Token": admin["csrf"]}
        assert (
            await client.post(
                "/devops/api/password",
                json={"current": initial, "password": NEW, "confirmation": NEW},
                headers=headers,
            )
        ).status == 200
        assert (await client.get("/devops/api/state")).status == 200
        response = await client.get("/devops/api/users")
        assert response.status == 200 and "password" not in (await response.text())
    finally:
        await client.close()


def test_concurrent_admin_disables_cannot_remove_last_enabled_admin(accounts):
    from concurrent.futures import ThreadPoolExecutor

    store, admin, _, student, _, _ = accounts
    with store.connect() as db:
        db.execute("update users set admin=1 where id=?", (student["user_id"],))
    promoted = store.session(store.login("student", PASSWORD, "fixture"))

    def disable(actor, target):
        try:
            store.set_enabled(actor, target, False)
            return True
        except (ValueError, PermissionError):
            return False

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(
            pool.map(
                lambda args: disable(*args),
                [(admin, promoted["user_id"]), (promoted, admin["user_id"])],
            )
        )
    assert sum(results) == 1
    with store.connect() as db:
        assert (
            db.execute(
                "select count(*)from users where admin=1 and disabled=0"
            ).fetchone()[0]
            == 1
        )


def test_nonadmin_reset_is_denied_before_password_derivation(accounts, monkeypatch):
    import devops_quests.store as module

    store, admin, _, student, _, _ = accounts
    calls = []
    monkeypatch.setattr(
        module, "password_hash", lambda password: calls.append(password)
    )
    with pytest.raises(PermissionError, match="admin"):
        store.reset_password(student, admin["user_id"], NEW)
    assert calls == []
