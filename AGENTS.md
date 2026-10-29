# Development and delivery

For every quest-editing task, follow [docs/quest-authoring.md](docs/quest-authoring.md)
and cite the relevant principle numbers in the PR.

Work only in the authorized scope. Preserve accounts, progress, pending briefing hints,
Lab files and unrelated Docker resources. Never add AI attribution or contributor trailers.
No default credentials, personal infrastructure, user databases, logs or private keys belong here.

In the maintainer layout (a bare clone with worktrees) treat the `main` worktree as read-only
(update and status only): create a sibling worktree on a new branch from `origin/main` for
every task (`git -C main worktree add ../<task> -b <branch> origin/main`), push that branch
and open a PR. Never commit or push to `main` directly; remove finished worktrees with
`git worktree remove`.

Use one writer per worktree. Independent read-only review must cover the final changed
content before commit/publication; later source edits need renewed review. Keep evidence
outside Git. Verify actual entrypoints and fixture layouts before changing production behavior.

## Delivery rules

- A normal task ends when its reviewed PR is merged to main after green CI; do not tag,
  release or deploy as part of that task. The owner previews merged main locally using
  the persistent preview worktree described in CONTRIBUTING.md.
- A release is a separate task created and authorized by the owner. Its scope includes
  tagging, artifacts and deployment. Always require green CI and smoke after deployment;
  CI never starts sandboxes by default.
- Database schema changes: rehearse rollback and compare progress hashes.
- Interface changes: headed screenshots of the affected screens, using synthetic users.
- Level changes: run the matrix only for affected levels; solutions are included for this proof.
- Keep release artifacts/checksums/image digests bound to the source commit. Do not move tags.
- Deploy by immutable version/digest; block active attempts/Labs and pending briefing hints.
- Do not publish, merge or deploy without the owner's authorization.

Validate with `.venv/bin/python -m pytest -q`, `npm test`, `ruff check .` and
`python scripts/validate_i18n.py`. Excerpt provenance, code-block parity and diagram tests
are required. Native Linux amd64 is the qualified target; do not invent portability claims.
