import json
import shutil

import pytest
import yaml

from devops_quests.catalog import ROOT, Catalog
from devops_quests.i18n import Resources


def test_native_quest_structure_and_all_original_languages():
    catalog = Catalog()
    assert len(catalog.quests) >= 40
    for number, quest in catalog.quests.items():
        assert isinstance(quest["title"], str)
        assert set(catalog.text(number, quest["title"])) >= {"en", "ru"}
        public = catalog.public(number, hints=3, debrief=True)
        assert isinstance(public["title"], dict)
        assert all(
            "check" not in goal
            for stage in public["stages"]
            for goal in stage["objectives"]
        )
        for stage in quest["stages"]:
            assert all(
                isinstance(goal["text"], str) and goal["check"]
                for goal in stage["objectives"]
            )


def test_new_language_is_discovered_without_code_and_partial_text_falls_back(tmp_path):
    root = tmp_path / "catalog"
    shutil.copytree(ROOT / "locales", root / "locales")
    (root / "locales/pl").mkdir()
    (root / "locales/pl/ui.json").write_text(json.dumps({"nav.map": "Mapa"}))
    resources = Resources(root)
    assert "pl" in resources.languages
    assert resources.preferences("pl", "ru") == {"primary": "pl", "translation": "ru"}
    with pytest.raises(ValueError):
        resources.preferences("../../elsewhere", "ru")
    assert Resources.values({"en": {"title": "English"}, "pl": {}}, "title") == {
        "en": "English"
    }
    with pytest.raises(ValueError):
        Resources.values({"en": {}, "pl": {"title": "Polski"}}, "title")


async def test_preferences_are_per_user_authenticated_and_csrf_protected(tmp_path):
    import asyncio

    from aiohttp.test_utils import TestClient, TestServer

    from devops_quests.engine import Engine
    from devops_quests.server import make_app
    from devops_quests.store import Store

    class FixtureEngine(Engine):
        async def background(self):
            await asyncio.Event().wait()

    store = Store(tmp_path / "profiles/progress.db")
    token = store.login("admin", store.bootstrap().read_text().strip(), "fixture")
    admin = store.session(token)
    store.add_user("student", "long-fixture-password", admin)
    catalog = Catalog()
    client = TestClient(
        TestServer(make_app(store, catalog, FixtureEngine(store, catalog, object())))
    )
    await client.start_server()
    try:
        assert (await client.get("/api/locales")).status == 200
        assert (
            await client.post(
                "/api/preferences", json={"primary": "ru", "translation": "en"}
            )
        ).status == 401
        client.session.cookie_jar.update_cookies({"devops_quests_session": token})
        origin = str(client.make_url("/")).rstrip("/")
        assert (
            await client.post(
                "/api/preferences",
                json={"primary": "ru", "translation": "en"},
                headers={"Origin": origin},
            )
        ).status == 403
        headers = {"Origin": origin, "X-CSRF-Token": admin["csrf"]}
        assert (
            await client.post(
                "/api/preferences",
                json={"primary": "ru", "translation": "en"},
                headers=headers,
            )
        ).status == 200
        data = await (await client.get("/api/state")).json()
        assert data["preferences"] == {"primary": "ru", "translation": "en"}
        assert (
            await client.post(
                "/api/preferences",
                json={"primary": "../../en", "translation": "ru"},
                headers=headers,
            )
        ).status == 400
        student = store.login("student", "long-fixture-password", "fixture")
        assert store.preferences(store.session(student)["user_id"]) == {
            "primary": None,
            "translation": None,
        }
        assert store.progress(admin["user_id"]) == []
        assert Store(store.path).preferences(admin["user_id"]) == {
            "primary": "ru",
            "translation": "en",
        }
    finally:
        await client.close()


async def test_failed_final_check_has_goal_reasons_and_alias_trace(tmp_path):
    import subprocess

    from devops_quests.engine import Engine
    from devops_quests.store import Store

    store = Store(tmp_path / "progress.db")
    token = store.login("admin", store.bootstrap().read_text().strip(), "fixture")
    run = store.create_run(store.session(token)["user_id"], 1, "normal")

    class Runtime:
        def exec(self, *args, **kwargs):
            return subprocess.CompletedProcess(
                [], 1, "", "rollout not ready; token=fixture-canary"
            )

    engine = Engine(store, Catalog(), Runtime())
    result = await engine.poll(run, final=True)
    feedback = result["check_result"]
    assert feedback["status"] == "failed" and feedback["remaining"][0]["objective"] == 0
    assert "rollout not ready" in feedback["remaining"][0]["detail"]
    assert "fixture-canary" not in feedback["remaining"][0]["detail"]
    assert result["status"] == "active" and store.progress(run["user_id"]) == []
    engine.command(result, "k get pods")
    run = store.run(run["id"], run["user_id"])
    assert run["commands"] == ["k get pods"]
    engine.aliases["tf"] = "tofu"
    engine.command(run, "tf plan -var token=another-canary")
    run = store.run(run["id"], run["user_id"])
    assert run["commands"][-1] == "tf plan -var token=[REDACTED]"


def test_repository_language_resources_and_guide_code_are_complete():
    from scripts.validate_i18n import audit

    result = audit()
    assert result["errors"] == [], result["errors"]
    assert result["stale"] == [], result["stale"]
    assert result["missing"] == {}, result["missing"]


def test_validator_rejects_missing_english_changed_code_and_stale_translation(tmp_path):
    from scripts.validate_i18n import audit, extract_source

    root = tmp_path / "repo"
    shutil.copytree(ROOT / "locales", root / "locales")
    shutil.copytree(ROOT / "quests/001", root / "quests/001")
    shutil.copytree(
        ROOT / "docs/guides/kubernetes-4", root / "docs/guides/kubernetes-4"
    )
    item = json.loads((ROOT / "docs/guide-excerpts.json").read_text())["kubernetes-4"]
    (root / "docs/guide-excerpts.json").write_text(json.dumps({"kubernetes-4": item}))
    message = root / "quests/001/i18n/en.yaml"
    values = yaml.safe_load(message.read_text())
    del values["title"]
    message.write_text(yaml.safe_dump(values))
    translation = root / "docs/guides/kubernetes-4/i18n/en.yaml"
    values = yaml.safe_load(translation.read_text())
    values["source_hash"] = "0" * 64
    values["text"] = values["text"].replace("apiVersion:", "changedApiVersion:")
    translation.write_text(yaml.safe_dump(values))
    result = audit(root)
    assert any(e["error"] == "missing_english_key" for e in result["errors"])
    assert any(e["error"] == "code_blocks_changed" for e in result["errors"])
    assert any(e["reason"] == "snapshot_changed" for e in result["stale"])
    original = yaml.safe_load(
        (root / "docs/guides/kubernetes-4/i18n/ru.yaml").read_text()
    )["text"]
    vault = tmp_path / "vault"
    source = vault / item["source"]
    source.parent.mkdir(parents=True)
    source.write_text(original + "\nChanged source text.\n")
    assert any(
        e["reason"] == "vault_source_changed" for e in audit(root, vault)["stale"]
    )
    assert extract_source(vault, item)[1] == 1


@pytest.mark.parametrize(
    "command",
    [
        "kubectl config set-credentials x --token fixture-credential",
        'curl --secret "fixture credential"',
        "tofu plan --api-key 'fixture credential'",
        "helm x --password=fixture-credential",
        'cat token="fixture credential"',
    ],
)
def test_trace_redacts_separated_and_quoted_secret_flags(command):
    from devops_quests.engine import Engine

    result = Engine.redact(command)
    assert "fixture" not in result
    assert "[REDACTED]" in result


@pytest.mark.parametrize(
    ("detail", "key"),
    [
        ("error: timed out waiting for the condition on deployment/relay", "timeout"),
        ("Error from server (Forbidden): denied", "denied"),
        ("No such file or directory", "missing"),
        ("rollout not ready", "not_ready"),
        ("Unsupported argument", "configuration"),
        ("different output", "unsatisfied"),
        ("", "no_detail"),
    ],
)
def test_probe_failure_has_localizable_cause(detail, key):
    from devops_quests.engine import Engine

    assert Engine.probe_reason(detail) == "checks.cause." + key
