"""Progress safety and read-only spoken-interview practice contracts."""

import asyncio

import yaml
from aiohttp.test_utils import TestClient, TestServer

from devops_quests.catalog import ROOT, Catalog
from devops_quests.engine import Engine
from devops_quests.server import make_app
from devops_quests.store import Store


def test_inserted_levels_never_lock_previously_completed_quests():
    catalog = Catalog.__new__(Catalog)
    catalog.quests = {number: {} for number in [1, 2, 3, 11, 21, 51, 81]}
    catalog.released = (1, 2, 3, 11, 21, 51, 81)
    completed = {1, 2, 3, 21, 51, 81}
    assert catalog.opened(completed) == completed | {11}
    assert catalog.opened({1}) == {1, 2}


def test_interview_bank_only_reveals_completed_practical_topics():
    catalog = Catalog()
    bank = catalog.interview({1})
    assert all(group["level"] == 1 for group in bank["completed"])
    assert bank["theory"], "Cloud/service-mesh questions must not require a cloud lab"
    for group in [*bank["completed"], *bank["theory"]]:
        assert 2 <= len(group["questions"]) <= 3
        for question in group["questions"]:
            assert question["prompt"]["en"] and question["points"]
            assert all(point["en"] for point in question["points"])
    assert catalog.interview(set())["completed"] == []


def test_book_map_resolves_to_playable_topics_and_original_oral_questions():
    catalog = Catalog()
    assert set(catalog.quests) == set(range(1, 131))
    coverage = yaml.safe_load((ROOT / "docs/book-coverage.yaml").read_text())
    assert [row["chapter"] for row in coverage["chapters"]] == list(range(1, 19))
    theory = {topic["id"] for topic in catalog.interview_topics}
    for row in coverage["chapters"]:
        assert row["levels"] or row["interview_topics"]
        assert set(row["interview_topics"]) <= theory
        for number in row["levels"]:
            quest = catalog.quests[number]
            assert quest.get("book") and 2 <= len(quest["questions"]) <= 3
            bank = catalog.interview({number})["completed"]
            assert any(group["level"] == number for group in bank)
    chapters = {row["chapter"]: set(row["levels"]) for row in coverage["chapters"]}
    for number, quest in catalog.quests.items():
        if quest.get("book"):
            assert number in chapters[quest["book"]["chapter"]]


def test_all_interview_source_references_supply_the_frontend_section_variable():
    catalog = Catalog()
    bank = catalog.interview(set(catalog.quests))
    for group in bank["completed"] + bank["theory"]:
        assert isinstance(group["book"]["section"], str)
        assert group["book"]["section"].strip()


async def test_interview_page_is_authenticated_and_does_not_record_attempts(tmp_path):
    class QuietEngine(Engine):
        async def background(self):
            await asyncio.Event().wait()

    store = Store(tmp_path / "profile/progress.db")
    token = store.login("admin", store.bootstrap().read_text().strip(), "fixture")
    catalog = Catalog()
    client = TestClient(
        TestServer(make_app(store, catalog, QuietEngine(store, catalog, object())))
    )
    await client.start_server()
    try:
        assert (await client.get("/api/interview")).status == 401
        client.session.cookie_jar.update_cookies({"devops_quests_session": token})
        before = store.path.read_bytes()
        response = await client.get("/api/interview")
        assert response.status == 200
        data = await response.json()
        assert data["theory"] and data["completed"] == []
        assert (await client.get("/interview")).status == 200
        assert store.path.read_bytes() == before
        assert "recording" not in data and "score" not in data
    finally:
        await client.close()
