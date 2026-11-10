# Contributing

Use a topic branch and a pull request. Run `make install`, the unit/JS tests, Ruff and
`scripts/validate_i18n.py`. Default CI needs no credentials and creates no Docker sandboxes.

To add a level, append its stable ID in `levels.yaml`, add `quests/<id>/quest.yaml`,
original localized resources, scoped check scripts and a solution under `solutions/`.
Checks must verify the requested behavior, not only search command history. Declare the
actual dependencies and cleanup only positively owned resources. Add meaningful content
and boundary tests. Never renumber existing IDs or copy book prose/questions.

When editing a quest, prefer a specific guide section or per-hint anchor for each hint
when it helps the learner find the relevant explanation. Add any needed guide anchors
and navigation support as part of that future edit; existing quests need no bulk rewrite.
Consecutive revealed hints with the same link show it only once.

Run real integration only on an isolated Linux host with disposable synthetic state:
`DQ_INTEGRATION=1 .venv/bin/python -m pytest 'tests/test_quests.py::test_quest[ID]' -q`.
Stop the app first; the fixture intentionally holds its runtime lock. Changes to levels
require only their affected matrix; text-only quest edits need none. Do not use your live
learning profile for tests.

CI (`.github/workflows/ci.yml`) runs once per pull request commit and on `main`: Ruff, the full
pytest suite, `npm test`, `validate_i18n.py` and a package build. It never starts sandboxes.
Locally, run the fast checks from `AGENTS.md` and the tests for the areas you touched; the full
suite in CI is the merge gate.

Guides are curated in `docs/guide-lessons.yaml`, `docs/guide-topics.yaml` and localized
snapshots under `docs/guides/`. The English `en.yaml` text is the source of truth: after editing
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

## Local image ownership across worktrees

Source bootstrap builds use `devops-quests/<namespace>/kind:0.1.0` and
`devops-quests/<namespace>/workstation:0.1.0` for the two mutable tags. The default namespace
is the sanitized checkout directory name plus the first 12 SHA-256 characters of its
resolved absolute path. Two checkouts with the same basename in different directories
therefore have distinct namespaces. Moving a checkout changes its default namespace.

`DQ_IMAGE_NAMESPACE` overrides the default: 1–64 lowercase letters, digits or hyphens,
starting and ending with a letter or digit. Use a unique value for each checkout; reusing an override
explicitly shares ownership and allows retagging. Keep the override consistent when
building, listing and cleaning images. Print the effective namespace from that checkout:

```sh
python -m scripts.image_tags
```

Main and preview follow the same naming rule on their next source build. A build-script
update invalidates the verified asset receipt, so preview needs one `make bootstrap`
after update. Cache verification is unchanged. For the same image IDs, the existing
`.state/built-image.json`, `kind-image.json` and `lab-images.json` retain the exact
legacy bytes: Lab profile versions hash these files. Runtime image IDs remain pinned.
No namespace bookkeeping is added to those files. List actual build tags by namespace
using the command below.
Existing legacy `devops-quests/*:0.1.0` and `dq-lab-diagnostic:*` host tags are left
untouched; do not remove them from a task worktree. Release digest references and
release publication are separate from local source-build tags.

The Lab diagnostic tag remains `dq-lab-diagnostic:<sha256(source)[:20]>`, shared by
checkouts with identical source. `make bootstrap` / `make lab-assets` reuses an existing
image only when it carries `devops-quests.lab-asset=true`, without Go or Docker builds.
A tag without that label causes an error and is never overwritten. An absent tag is
built once; a per-user lock in `/tmp/devops-quests-images-<uid>/` serializes cooperating
source builders. Do not remove diagnostic tags as part of worktree cleanup: other
checkouts and saved Labs may use them. An observed pre-existing limitation is that
same-source diagnostic rebuilds can yield different image IDs; preserving an existing
labeled image avoids that rebuild. Bit-reproducible builds are outside this change.

To list images owned by the current checkout (no Docker resources are removed):

```sh
namespace=$(python -m scripts.image_tags)
docker --host unix:///var/run/docker.sock image ls --no-trunc \
  --filter "reference=devops-quests/$namespace/*:*"
```

After stopping and disposing of only this checkout's sandboxes/Labs through the app,
remove a specific tag from the listing, for example:

```sh
docker --host unix:///var/run/docker.sock image rm \
  "devops-quests/$namespace/workstation:0.1.0"
```

Use exact tags inside your namespace, never image IDs, `--force`, global image pruning
or tags belonging to another checkout. Different namespaces may refer to the same
immutable image ID; deleting one tag retains other references. `git worktree remove`
removes checkout files, including local image metadata, but leaves Docker tags, images,
containers, networks and volumes behind. Record your namespace/tags before removing
the checkout, and clean only the resources whose ownership you have verified.
