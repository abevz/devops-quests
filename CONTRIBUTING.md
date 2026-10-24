# Contributing

Use a topic branch and a pull request. Run `make install`, the unit/JS tests, Ruff and
`scripts/validate_i18n.py`. Default CI needs no credentials and creates no Docker sandboxes.

To add a level, append its stable ID in `levels.yaml`, add `quests/<id>/quest.yaml`,
original localized resources, scoped check scripts and a solution under `solutions/`.
Checks must verify the requested behavior, not only search command history. Declare the
actual dependencies and cleanup only positively owned resources. Add meaningful content
and boundary tests. Never renumber existing IDs or copy book prose/questions.

Run real integration only on an isolated Linux host with disposable synthetic state:
`DQ_INTEGRATION=1 .venv/bin/python -m pytest 'tests/test_quests.py::test_quest[ID]' -q`.
Stop the app first; the fixture intentionally holds its runtime lock. Changes to levels
require only their affected matrix. Do not use your live learning profile for tests.

Guides are curated in `docs/guide-lessons.yaml`, `docs/guide-topics.yaml` and localized
snapshots under `docs/guides/`. The Russian `ru.yaml` text is the source of truth: after editing
it, run `python -m scripts.guide_excerpts` to re-hash it, then update the stale translations;
translations must preserve operational code. Diagrams render locally with strict SVG
handling. Screenshots use a synthetic `demo` account and must not reveal passwords or keys.

Follow [AGENTS.md](AGENTS.md), [SECURITY.md](SECURITY.md) and [release rules](docs/RELEASING.md).
