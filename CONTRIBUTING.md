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

## Maintainer preview and releases

A normal task ends with its reviewed PR merged to main after green CI. Tags, releases
and deployment belong to a separate release task created and authorized by the owner,
after reviewing the accumulated changes locally. Follow the release rules for artifact
identity, upgrade blocking and post-deployment smoke checks.

In the bare-clone maintainer layout, create a persistent preview branch and worktree
tracking `origin/main` (the `main` worktree is already checked out):

```sh
git -C main fetch origin main
git -C main worktree add ../preview -b preview-local origin/main
cd preview
make install
make up
```

On later visits, stop the preview app before updating, then run `git pull --ff-only`
and `make up` from `preview`. If dependencies or bundles change, run `make install`
again. The app listens at <http://127.0.0.1:8766/>; stop any other app using that port.
Create the first synthetic administrator in a second terminal from `preview` with
`.venv/bin/python -m devops_quests init-admin --username demo` and enter a new password
at the prompt. Use this account to log in; do not use a real learning profile.

The preview's database is `preview/.state/runtime/progress.db`, separate from other
worktrees. With the preview app stopped, `make reset` resets Training Bays but retains
accounts, progress and saved Labs; it is not a database reset. To start over, delete its Labs
through the UI first if any exist, and only after confirming its data can be discarded,
remove `preview/.state/runtime/`. This permanently deletes that preview's accounts,
progress, Lab records and files. Never remove another installation's state or use a
global Docker prune.
