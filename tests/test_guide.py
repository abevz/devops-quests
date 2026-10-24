import hashlib
import json
from types import SimpleNamespace

from aiohttp.test_utils import TestClient, TestServer

from devops_quests.catalog import Catalog
from devops_quests.engine import Engine
from devops_quests.server import COOKIE, make_app
from devops_quests.store import Store


async def test_authenticated_guide_safe_payload_theme_and_navigation(tmp_path):
    root = tmp_path / "catalog"
    (root / "docs").mkdir(parents=True)
    (root / "docs/guide-excerpts.json").write_text(
        json.dumps(
            {
                "fixture": {
                    "heading": "A <title>",
                    "text": "</script><script>bad()</script>\n\n> [!note] A\n> text",
                    "source": "Guide.md",
                    "line": 3,
                    "obsidian": "obsidian://open?vault=example&file=Guide",
                },
            }
        )
    )
    store = Store(tmp_path / "profile.db")
    token = store.login("admin", store.bootstrap().read_text().strip(), "fixture")

    class FixtureEngine(Engine):
        async def background(self):
            import asyncio

            await asyncio.Event().wait()

    catalog = Catalog()
    item = json.loads((root / "docs/guide-excerpts.json").read_text())["fixture"]
    item["source_hash"] = hashlib.sha256(item["text"].encode()).hexdigest()
    catalog.guides = {"fixture": item}
    catalog.guide_messages = {
        "fixture": {
            lang: {
                "heading": item["heading"],
                "text": item["text"],
                "source_hash": item["source_hash"],
            }
            for lang in ["en", "ru"]
        }
    }
    client = TestClient(
        TestServer(
            make_app(store, catalog, FixtureEngine(store, catalog, SimpleNamespace()))
        )
    )
    await client.start_server()
    try:
        response = await client.get("/guide/fixture")
        assert response.status == 401
        headers = {"Cookie": f"{COOKIE}={token}"}
        response = await client.get(
            "/guide/fixture", headers=headers, allow_redirects=False
        )
        assert response.status == 302
        assert response.headers["Location"] == "/guides#guide=fixture"
        response = await client.get("/api/guide/fixture", headers=headers)
        assert response.status == 200
        payload = await response.json()
        # JSON content remains inert until the existing safe Markdown renderer
        # handles it. There is no interpolated HTML/script payload any more.
        assert payload["content"]["en"] == item["text"]
        assert payload["titles"]["en"] == "A <title>"
        assert "obsidian://" not in json.dumps(payload)
        assert "vault=example" not in json.dumps(payload)
        assert "script-src 'self'" in response.headers["Content-Security-Policy"]
    finally:
        await client.close()
