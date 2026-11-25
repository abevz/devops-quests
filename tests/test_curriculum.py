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


def test_interview_bank_lists_all_questions_and_marks_quest_completion():
    catalog = Catalog()
    bank = catalog.interview({1})
    quests = {group["level"]: group for group in bank["quests"]}
    assert set(quests) == {number for number, quest in catalog.quests.items() if quest.get("questions")}
    assert {group["id"] for group in bank["theory"]} == {topic["id"] for topic in catalog.interview_topics}
    for number, group in quests.items():
        assert group["completed"] is (number == 1)
        assert group["difficulty"] == catalog.by_id[number]["difficulty"]
        assert group["topic"] == catalog.by_id[number]["track"]
        assert len(group["questions"]) == len(catalog.quests[number]["questions"])
    for group, topic in zip(bank["theory"], catalog.interview_topics, strict=True):
        assert "completed" not in group
        assert len(group["questions"]) == len(topic["questions"])
    seen = set()
    for group in [*bank["quests"], *bank["theory"]]:
        for question in group["questions"]:
            assert question["id"] not in seen
            seen.add(question["id"])
            assert question["prompt"]["en"] and question["points"]
            assert all(point["en"] for point in question["points"])
    assert all(not group["completed"] for group in catalog.interview(set())["quests"])


def test_book_map_resolves_to_playable_topics_and_original_oral_questions():
    catalog = Catalog()
    assert set(catalog.quests) == set(range(1, 131))
    coverage = yaml.safe_load((ROOT / "docs/book-coverage.yaml").read_text())
    assert [row["chapter"] for row in coverage["chapters"]] == list(range(1, 19))
    theory = {topic["id"] for topic in catalog.interview_topics}
    bank_levels = {group["level"] for group in catalog.interview(set())["quests"]}
    for row in coverage["chapters"]:
        assert row["levels"] or row["interview_topics"]
        assert set(row["interview_topics"]) <= theory
        for number in row["levels"]:
            quest = catalog.quests[number]
            assert quest.get("book") and 2 <= len(quest["questions"]) <= 3
            assert number in bank_levels
    chapters = {row["chapter"]: set(row["levels"]) for row in coverage["chapters"]}
    for number, quest in catalog.quests.items():
        if quest.get("book"):
            assert number in chapters[quest["book"]["chapter"]]


def test_all_interview_source_references_supply_the_frontend_section_variable():
    catalog = Catalog()
    bank = catalog.interview(set(catalog.quests))
    for group in bank["quests"] + bank["theory"]:
        assert isinstance(group["book"]["section"], str)
        assert group["book"]["section"].strip()


async def test_interview_page_is_authenticated_and_does_not_record_attempts(tmp_path):
    class QuietEngine(Engine):
        async def background(self):
            await asyncio.Event().wait()

    store = Store(tmp_path / "profile/progress.db")
    token = store.login("admin", store.bootstrap().read_text().strip(), "fixture")
    user = store.session(token)["user_id"]
    store.finish(store.create_run(user, 1, "normal"))
    store.add_user("learner", "fixture-password", store.session(token))
    learner = store.login("learner", "fixture-password", "fixture")
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
        assert data["theory"]
        assert {group["level"] for group in data["quests"] if group["completed"]} == {1}
        client.session.cookie_jar.update_cookies({"devops_quests_session": learner})
        response = await client.get("/api/interview")
        assert response.status == 200
        learner_data = await response.json()
        assert learner_data == catalog.interview(set())
        assert (await client.get("/assets/interview.mjs")).status == 200
        assert (await client.get("/interview")).status == 200
        assert store.path.read_bytes() == before
        assert "recording" not in data and "score" not in data
    finally:
        await client.close()
